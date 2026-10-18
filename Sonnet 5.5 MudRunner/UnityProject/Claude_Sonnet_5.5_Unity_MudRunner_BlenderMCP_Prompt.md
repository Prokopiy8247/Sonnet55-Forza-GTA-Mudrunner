# Claude Sonnet 5.5 — Unity 6 + Blender MCP MudRunner-Style Off-Road Mud Physics Benchmark

## Mission

You are the sole lead developer, technical artist, physics programmer and QA engineer of the **existing Unity 6 project in the project folder currently opened in this Claude agent**.

Your task is to build the most convincing and polished **MudRunner-style off-road driving simulation** you can achieve during this autonomous development session.

The game must be an **original project**. Use *MudRunner* (and its lineage, *Spintires* and *SnowRunner*) only as a mechanics and feature-scope reference. Do not copy their maps, names, logos, vehicle models, textures, audio, UI artwork, code or any proprietary content. Choose your own original game title.

### The defining design pillars

1. **Mud is the main character.** The whole game is about heavy vehicles moving through deep, deformable, treacherous ground. **The primary focus of this project is the physics of the mud and the physics of the vehicle suspension and wheels.** Everything else (art, UI, objectives) supports that.
2. **Route reading.** The player must **find a path through the terrain so the vehicle does not get stuck**. The world therefore needs readable terrain: visible differences between firm ground, wet ground, shallow mud, deep mud, bog and water; a choice between a long safe route and a short risky one; slopes, ruts, rocks, logs and river crossings.
3. **Weight, momentum and consequences.** Heavy vehicles that sink, spin, slide, tilt, flex their suspension and get stuck for believable reasons — then can be recovered with the right tools (differential lock, low gear, all-wheel drive, winch, careful throttle).
4. **Slow, tense, satisfying driving.** Not a racing game. A moment of "will it make it?" must be possible and visible on camera.

---

# 0. Research first — go to the internet

Before designing the physics, **use the web search / web fetch tools available to this agent to research MudRunner, Spintires and SnowRunner**. If no web tool is available in this session, say so explicitly in `RESEARCH_NOTES.md` and continue from your own knowledge.

Research at least:

- how the ground is represented and deformed (heightfield/vertex displacement, mud layers, viscosity, wetness, ruts), and how vehicles interact with it (sinkage, traction, rolling resistance, wheel spin digging deeper);
- vehicle systems: suspension types and articulation, tire types and sizes, differentials and locks, all-wheel drive, gear ranges, fuel, damage, engine/water behaviour;
- recovery tools: winch behaviour, anchor points, towing, other vehicles;
- water: depth, current, buoyancy and floating;
- cargo and trailers (weight, balance, tipping);
- map design: how routes, dead ends and shortcuts are laid out, navigation by map and compass, how terrain cues tell the player where it is safe;
- HUD and controls conventions;
- developer talks, interviews and community analyses about the mud and terrain technology.

Then research the Unity side: the Unity 6 documentation on `Terrain`/`TerrainData` runtime editing (`SetHeights`, `SetHeightsDelayLOD`, `SyncHeightmap`, `DirtyHeightmapRegion`, alphamaps/splat layers), `WheelCollider` and its friction model, `ArticulationBody`, joints (`ConfigurableJoint`, `SpringJoint`), `Physics` settings, Burst/Jobs, the URP shader/terrain shader options in the version installed, and the Unity CLI. Prefer official documentation.

Known pitfalls to account for (verify them): `TerrainData.SetHeights` over a large region is slow, so modify small patches and use the delayed-LOD variant; terrain edits made at runtime in the editor can persist into the `TerrainData` asset, so instantiate/clone the data at startup; updating a heightfield collider is expensive, so patch and throttle updates; the visible surface and the physical surface do not have to be the same data (see Section 5).

Write the results to **`RESEARCH_NOTES.md`** in the project folder: a feature inventory; for each notable mechanic **ADOPT / ADAPT / SKIP** with a short reason; source URLs; and the final prioritized feature list you commit to. Do not copy text from sources; summarize in your own words.

---

# 1. Existing project and environment

Work directly in the current project folder (it contains `Assets/`, `Packages/`, `ProjectSettings/`). **Do not create another nested Unity project.**

Known environment (verify each item, do not blindly trust):

```text
Project folder:    the folder currently opened in this Claude agent
                   (W:\YouTube\Claude Sonnet 5.5\MudRunner\UnitySonnet5.5MudRunner)
Unity editor:      6000.6.0f1  (ProjectSettings/ProjectVersion.txt)
Editor binary:     C:\Program Files\Unity\Hub\Editor\6000.6.0f1\Editor\Unity.exe
Render pipeline:   Universal Render Pipeline (com.unity.render-pipelines.universal 17.6.0 in manifest.json)
Built-in modules:  physics, terrain, terrainphysics are enabled
Unity CLI:         C:\Users\<user>\AppData\Local\Unity\bin\unity.exe  (1.0.0-beta.12)
Language:          C#
IDE:               Visual Studio Community (W:\Visual Studio)
Git:               W:\Git\Git\cmd\git.exe (on PATH)
```

Technical defaults:

- **C#** for all gameplay, physics and tooling code; keep it organized in assemblies/namespaces under `Assets/Game/...`.
- **URP**. Use Shader Graph or hand-written HLSL for the mud/terrain visuals as appropriate to the installed version. Keep the visual pipeline simple and robust.
- Unity **Terrain** is the default ground representation, but you may use a project-owned heightfield/mesh-grid system if testing shows it is better for deformation (Section 5). Justify the choice in `DEVELOPMENT.md`.
- Use the **Input System** package if it is the project default; otherwise the legacy input is acceptable.
- Use Unity's built-in packages only (no Asset Store assets, see Section 2.3). Official Unity packages (Input System, Cinemachine, Shader Graph, Terrain Tools, Test Framework, Burst, Collections, Jobs) may be added to `Packages/manifest.json` where they genuinely help.
- Build the scene content with **reproducible Editor scripts** (`Assets/Editor/...`, invoked through menu items, `-executeMethod` or the Unity CLI) rather than hand-editing serialized scene YAML. The project should be regenerable from code plus Blender exports.

## 1.1 How to drive the engine (autonomy)

Use the best available automation path, in this order:

1. If this session exposes a **Unity MCP** server, use it. Do not register new MCP servers or change global/user settings yourself.
2. The **Unity CLI** (`unity.exe`, installed per user): it can open a project with the right editor, show the live state of connected editors, list and execute commands on a running editor, recompile and report errors, run EditMode/PlayMode tests, run in batch mode and build. Start with `unity skill show` (a task-oriented guide for agents) and `unity --help` / `unity <command> --help`. Some commands require the **Unity Pipeline** package in the project: check `Packages/manifest.json`; if it is absent, install it into this project following the Unity CLI documentation (`unity pipeline --help`). Do **not** change global CLI/client configuration, sign in or out of accounts, or run `unity mcp configure`.
3. Fallback: Unity batch mode (`Unity.exe -batchmode -nographics -projectPath <path> -executeMethod <Class.Method> -logFile <file> -quit`), reading the log for compile errors and exceptions.

You are responsible for compile errors, missing references, import problems and runtime exceptions. Do not ask me to click anything in the editor. Keep every setup step reproducible as a script.

---

# 2. Blender MCP — mandatory

The user created the master Blender file and started a dedicated Blender instance for this project.

```text
Blender host:        localhost
Blender port:        9891
Master Blender file: ./UnitySonnet5.5Mudrunner.blend   (in the project folder; note the lowercase "r" in "Mudrunner")
MCP server name:     expected to be `blender-mudrunner-unity` (declared in this project's .mcp.json)
                     - still discover and verify the actual enabled connection
```

The Blender scene is expected to be an **empty default scene** at the start (another agent already confirmed the connection and found only the default scene). Everything has to be created by you.

## 2.1 Routing rule

Choose the actual MCP connection exposed to this agent that is configured for **`localhost:9891`**. Determine its identity from the available tool descriptions. Do not reuse a server that points at another port, and do not invent names.

Before making any Blender changes:

1. Record the session start time (Section 15) and resolve the project directory.
2. Confirm that `UnitySonnet5.5Mudrunner.blend` exists in that directory.
3. Identify the MCP connection configured for `localhost:9891`.
4. Execute a real read-only Blender MCP call: inspect the open scene and obtain the full path of the current `.blend` file through an available permitted read-only operation.
5. Confirm that this path is the exact `UnitySonnet5.5Mudrunner.blend` in the project folder. A listening port or a matching basename alone is not confirmation.
6. Back up the master file before its first modification. Record the verified server/tool namespace, endpoint and full file path in `DEVELOPMENT.md` and the final report.

For every subsequent Blender operation: use only this verified connection; treat `UnitySonnet5.5Mudrunner.blend` as the canonical editable source; preserve unrelated content; organize generated assets in clearly named collections; save the master file regularly; keep exports and backups separate from the master file.

If the Blender MCP tools are unavailable, a call fails or the opened file does not match, report the exact blocker and the minimum correction. Do not write to another Blender instance, do not silently replace Blender-authored assets with Unity primitives, and do not claim a successful verification you did not perform.

Respect the connector's permissions and Safe Mode. Do not patch the add-on or bypass validation. Do not ask me to model, UV, rig, export, import or wire assets manually.

## 2.2 Blender visual QA loop

For every important hero asset (vehicles first):

1. model it through the verified Blender MCP connection;
2. create UVs and materials;
3. inspect it visually using viewport/render feedback and revise anything that looks broken or placeholder-quality;
4. save the Blender source;
5. export it (Section 2.4);
6. import it into Unity;
7. configure materials, colliders, physics components and gameplay scripts;
8. test it in Play Mode.

An asset is not finished because a file exists. It must look reasonable and work inside Unity.

## 2.3 No external asset shortcuts

Do not depend on the Unity Asset Store, Sketchfab, Poly Haven, Poly Pizza, AI 3D-generation services, ripped game assets or any downloaded vehicle/prop/terrain-texture pack. Create the important 3D assets yourself with Blender MCP and project-owned code. Unity built-in primitives may be used only as temporary stand-ins during development. Procedurally generated project-owned textures, materials, meshes and audio are allowed.

## 2.4 Blender → Unity export pipeline

```text
UnitySonnet5.5Mudrunner.blend -> Blender MCP edits -> save -> export FBX (glTF only if it validates better)
 -> Assets/Game/Art/... -> Unity import settings -> materials, colliders, prefabs -> gameplay scripts
```

- FBX is the primary interchange format for Unity. Author at real-world scale (1 Blender unit = 1 m) and verify scale, axes and pivots after import (apply transforms; check that +Z is forward in Unity for vehicles).
- Vehicles: chassis/body, cab, cargo bed or tank body, **separate wheel meshes with the pivot at the wheel centre**, **visible suspension parts** (axles, leaf/coil springs, shock absorbers, control arms/links) so suspension articulation is visible on camera, winch and bumper, lights, windows, snorkel/exhaust, interior suitable for a cockpit view. Use consistent part names (`Chassis`, `Wheel_FL`, `Wheel_FR`, `Wheel_RL`, ...).
- Provide simple collision proxies for vehicles (compound boxes/convex hulls) and for rocks/logs/props; do not rely on per-triangle mesh colliders for dynamic bodies.
- Provide LODs for vehicles and heavy props where it matters.
- Automate exports through the MCP and scripts; the master `.blend` is never used at runtime.

Organize the Blender file into clear collections, for example `MUDRUNNER_UNITY / Vehicles / Trailers_Cargo / Props_Nature / Props_Structures / Collision`. No unnamed `Cube.001` objects in final assets.

---

# 3. Autonomy and workflow

I am not a Unity expert. Do **not** expect me to create scenes, configure layers/physics settings, assign references, import assets or fix compile errors manually. Take ownership.

Before substantial work:

1. read this entire prompt and any local `CLAUDE.md`/`AGENTS.md`;
2. record the start timestamp (Section 15);
3. inspect the project (`ProjectSettings`, `Packages/manifest.json`, existing `Assets`), the installed editor and the Unity CLI;
4. verify the Blender connection (Section 2.1);
5. do the research (Section 0);
6. write a concise technical plan and a **physics prototype plan** (Section 5);
7. create a Unity `.gitignore` (`Library/`, `Temp/`, `Obj/`, `Logs/`, `UserSettings/`, `Builds/`, IDE folders) and initialize Git with a baseline commit if the folder is not already under version control;
8. create `DEVELOPMENT.md`, `FEATURE_MATRIX.md`, `RESEARCH_NOTES.md` and `SONNET_5.5_FINAL_REPORT.md`.

Then work autonomously; do not stop to ask for confirmation after each subsystem. If a feature becomes a deep blocker, preserve the working game, document the limitation, move on and return later. Never claim an unfinished feature works.

---

# 4. Vehicles

Create **at least three clearly different, Blender-authored off-road vehicles** (four if time allows) with distinct silhouettes, mass, tires, suspension and capabilities. Original designs only; no real manufacturer names or logos. Suggested spread:

1. **Light 4×4 scout** (about 1.5–2 t, narrow tires, lightweight, nimble but easily bogged in deep mud);
2. **Mid-size utility truck/SUV** (about 3–5 t, balanced, with a winch);
3. **Heavy 6×6 hauler** (about 8–12 t, large tires, high ground clearance, multiple axles, trailer/cargo capable);
4. optional: tracked or high-flotation ATV, tractor, or a trailer with load.

Every vehicle is **data-driven** (ScriptableObject or similar): mass and centre of mass, engine torque curve, gear ratios and ranges, drivetrain layout, differential configuration, tire dimensions and compound/tread/pressure class, suspension type, spring/damper/travel/anti-roll per axle, ground clearance, fuel tank, winch strength and length, water-fording depth, damage resistance.

Vehicle controls and systems (see Section 6): throttle, brake, steering, handbrake, gearbox with low/high range (automatic and manual), all-wheel-drive toggle, differential lock(s), engine on/off, fuel, headlights, winch, camera modes, vehicle reset/recover (limited), and entering/exiting or switching vehicles at garages.

---

# 5. The mud and terrain physics — the heart of the project

Design and build a **project-owned ground-interaction system**. This is the part that will be judged most strictly. Prototype it **first** (Section 12 priority 2–4) in a small test arena, before building the large map.

## 5.1 Surface model

The ground carries at least these properties per location (stored in compact data such as float textures/arrays, **not** per-object Nodes/GameObjects):

- **surface type**: firm soil/rock, grass/forest floor, packed dirt/gravel road, shallow mud, deep mud, bog/swamp, sand/silt (optional), shallow water, deep water;
- **viscosity / softness** (how easily a wheel sinks and how strongly mud resists);
- **wetness** (rain and puddles increase softness; drying is slow);
- **mud depth / sinkage field** (dynamic: how much the surface has been displaced);
- optional hidden "extrusion" or "depth" data painted by the level designer, so a patch can *look* ordinary but be much deeper.

## 5.2 Wheel-ground interaction

For each wheel, every physics step:

1. sample the ground under the contact patch (position, normal, surface type, viscosity, wetness, current sinkage);
2. compute **sinkage** as a function of wheel load, contact area (tire width/diameter/pressure), and softness; heavy narrow tires sink more than wide flotation tires;
3. compute **traction** from slip, sinkage, viscosity and tire tread/compound — the wheel can lose grip and **spin**, and a spinning wheel **digs itself deeper** (positive feedback) unless the player modulates the throttle, locks diffs or switches gear range;
4. compute **rolling/motion resistance** and **bulldozing resistance** from sinkage and vehicle speed;
5. **displace mud**: leave ruts behind wheels, push material into berms at the sides, let ruts slowly settle/fill depending on wetness; ruts must visibly persist and affect the next pass;
6. apply the resulting forces to the vehicle's rigid body at the wheel positions (so weight transfer, tilt and slide emerge from the physics);
7. when the **chassis/belly** touches the mud, apply additional drag/support ("high-centred"), so ground clearance matters;
8. feed the result into **audio** (squelch, splash, engine strain), **particles** (mud spray, water splashes) and **visuals** (wheel/vehicle dirt level increasing with time in mud — optional).

Being "stuck" must emerge from physics (traction available < resistance + slope), not from a scripted flag. Provide a **stuck detector** only for HUD/analytics.

## 5.3 Visible deformation

The player must *see* the ground deform. Choose and justify one of these, or a hybrid, after prototyping:

- real **heightfield modification** of Unity `Terrain` in small patches under the wheels (`SetHeightsDelayLOD` / `SyncHeightmap`), with cloned `TerrainData` at runtime and throttled collider updates;
- a **project-owned chunked mesh/heightfield** with its own collision shapes updated per local patch;
- **virtual sinkage**: keep the collision surface smooth and cheap, store the mud displacement in a separate field (texture/array), let wheels sink "virtually" using that field, and display the deformation through a vertex-displacement / parallax / normal-and-albedo-blend **shader** driven by the field texture, plus decals.

A reference approach from the genre: ground as a regular grid of vertices displaced by a height map, with a mud layer on top, wheel/ground forces computed from slip and load, and the displacement itself done on the GPU. You are free to do something different if it works better.

Requirements regardless of approach: deformation is local and cheap (only near vehicles), persistent for a long enough time to read as ruts, does not cause visible popping, and keeps the frame rate stable.

## 5.4 Water

- Shallow water (ford): modest drag, splash effects, visibly pushes the vehicle if there is a current.
- Deep water: buoyancy and drag; vehicles can float briefly or be swept away depending on weight and fording depth; engine drowning / stalling (stretch).
- Flowing rivers with a direction and strength are a high-value feature.

## 5.5 Slopes and obstacles

Mud on slopes must be treacherous: sliding downhill, losing traction on steep climbs, sideways drift on cambered tracks, rollover risk. Rocks, logs, stumps and ditches must behave physically (rigid bodies where it matters, static colliders otherwise). Logs can be dragged/pushed as optional sandbox objects.

---

# 6. Suspension, drivetrain and recovery

## 6.1 Suspension and wheels

- Independent per-wheel suspension with **spring, damper, bump stops and travel**, anti-roll bars, and **axle articulation** (solid axles flex independently side to side; one wheel can droop into a hole while the other stays on a rock).
- Stable behaviour at heavy mass and low speed: no jitter, no explosion, no sinking through the ground, no launching on contact with obstacles. Tune solver iterations, fixed timestep and substepping for the vehicle.
- Tires with realistic compliance (sidewall deflection/footprint growth with low pressure as a stretch).
- Choose and justify: Unity `WheelCollider` with custom friction/forces, a **project-owned raycast/spherecast suspension**, or `ArticulationBody`. Test quickly; keep the approach that is stable and expressive.
- Wheel meshes, suspension parts and axles must visibly follow the physics (including wheel droop and axle tilt).

## 6.2 Drivetrain

- Engine torque curve with RPM, inertia and a stall model; automatic and manual gearbox; **low and high range**; reverse.
- **Differentials**: open / locked front, rear and centre; **AWD toggle**; limited-slip as a stretch. Locked diffs increase traction but reduce steering and increase stress.
- **Fuel** consumption depending on load/throttle; refuelling at stations or via a garage/service point.
- **Damage** (stretch): engine/suspension/tire damage from heavy impacts and long deep-water driving; repair at a garage.

## 6.3 Recovery

- **Winch**: the player aims/selects an anchor (tree, post, rock, another vehicle or a placed ground anchor), the rope has a length limit and visible cable, tension and pulling force follow the vehicle's winch rating; reel in/out; the pulled vehicle's motion is physically plausible.
- **Towing** by a second vehicle (switching vehicles is acceptable) as a stretch.
- Limited **"recover vehicle"** reset with a cost (time/fuel/score) so a failed player is never permanently blocked, but the penalty is visible.

---

# 7. The world

## 7.1 Scale and structure

Build **one large wilderness map of roughly 1.5 km × 1.5 km (about 2.25 km²)** plus a dedicated **proving ground** (Section 7.3). The map is a muddy river valley / forest / swamp region with:

- a **base camp / garage** where vehicles are chosen, refuelled and repaired;
- a **fuel station** and one or two service/anchor points;
- **at least three route choices** between key points: a long but firm (and still muddy) track; a medium route with ruts and a ford; and a short, dangerous shortcut through a bog or steep mud climb;
- **river crossings** with fords of different depth and some broken or fragile bridges;
- hills of varied steepness with mud-covered slopes, forest sections with logs/rocks/stumps, a swamp basin, a clearing with a cabin or logging camp;
- landmarks and sight lines so the player can navigate by map and compass.

## 7.2 Readable terrain

The visual language of the ground is a gameplay system, not decoration. Make firm ground, wet ground, shallow mud, deep mud, bog and water visually distinguishable and consistent: colour/darkness/gloss differences, standing puddles, reflective water, vegetation type (reeds in bog, grass on firm ground), existing ruts, churned patches, moss, rocks. A careful player must be able to **read** the terrain and plan a route; a careless one gets stuck.

## 7.3 Proving ground

A compact test arena inside the project used for demos and QA: mud pits of increasing depth, a steep mud hill, a side-slope, an axle-articulation course (rocks and holes), a river ford with current, a log pile, winch anchor trees and a measuring area. It should also be reachable from the base camp or via the debug menu.

## 7.4 Weather and time

- Time of day with headlights/work lights; fog, overcast, rain (rain raises wetness and softness over time and makes puddles); optional clear weather.
- Moody, atmospheric, readable lighting. Gameplay readability is more important than cinematic drama.

---

# 8. Objectives and game flow (kept simple)

The core experience is free driving, but give the player a reason to plan a route:

- **delivery objectives**: reach marked destinations, optionally carrying a cargo (logs, barrels, crates) on a bed/trailer that adds weight and can be lost or damaged;
- a few **scenarios** of increasing difficulty (for example: light vehicle across a firm route; heavy truck with a log trailer across a bog; reach the cabin before the fuel runs out);
- an optional timer and fuel limit per scenario;
- a **free-drive mode** with no objectives.

No story or dialogue. Keep objective code small; the physics is the product.

---

# 9. Camera, HUD, controls and audio

**Camera**: third-person chase camera with orbit/zoom and collision; cockpit/driver view; a **wheel/suspension close-up camera** (very valuable for video); free camera in the debug menu.

**HUD**: speed, gear and range, AWD/diff-lock indicators, RPM, fuel, damage, winch state, compass and map/minimap, objective info, stuck warning, and an optional **physics overlay** showing per-wheel load, sinkage, slip, surface type and traction (debug toggle).

**Controls**: keyboard and mouse by default (WASD/arrows, space = handbrake, dedicated keys for AWD, diff lock, range, winch, camera, headlights, map, reset); a gamepad is a stretch goal after keyboard and mouse is stable. Provide an on-screen control help.

**Audio** (project-owned or procedural): engine load/RPM, gear grinding, tire squelch and suction, mud splashes, water, rain, wind, creaking suspension, winch tension, collisions, ambient forest/swamp sounds. No copyrighted audio.

---

# 10. Debug / benchmark menu — mandatory

A menu or console that makes the project easy to demo on YouTube:

- teleport to base, proving ground, route start/end points;
- switch/spawn any vehicle; attach/detach trailer and cargo;
- refuel, repair, flip-reset, free camera;
- set global mud depth/softness multiplier, rain on/off and wetness, time of day;
- toggle physics overlay, collider/force gizmos, slow motion;
- toggle AWD/diff lock states and winch auto-anchor for testing;
- show FPS, coordinates and the current surface type;
- run the **automated physics test suite** (Section 11).

---

# 11. Quality, automated physics testing and documentation

## 11.1 Honest status

Use only `WORKING`, `PARTIAL` or `NOT IMPLEMENTED` in `FEATURE_MATRIX.md` (columns: Feature | Status | Notes). Only mark `WORKING` if there is a functional in-game path. Do not populate menus with features that do not work.

## 11.2 Automated physics validation (important)

Write repeatable **automated drive tests** (a bot driver driven by scripted inputs plus Unity Test Framework PlayMode tests or editor-invoked test routines, runnable through the Unity CLI or batch mode) and record the numbers in `DEVELOPMENT.md`:

- each vehicle crosses firm ground, shallow mud and deep mud: sinkage depth, speed, time, success/failure;
- a light vehicle gets stuck in deep bog where a heavy/high-flotation vehicle passes;
- spinning wheels dig deeper than controlled throttle (demonstrable difference);
- diff lock/AWD/low range measurably improve a hill climb in mud;
- a winch pull recovers a stuck vehicle;
- suspension stability: no jitter/explosion over a rock course; axle articulation values;
- water fording: success below the rated depth, failure above it;
- performance: frame time with vehicles deforming terrain.

## 11.3 Continuous QA

Continuously: recompile and read the console, run tests, play the game in the editor or a batch run, capture screenshots of key situations, verify imported assets (scale, orientation, wheel pivots, colliders, materials), check missing references. Do not wait until the end to discover the project does not load.

## 11.4 Final validation

Before declaring completion verify at least: the project compiles with no errors; the main scene loads and starts in a vehicle; all listed vehicles are drivable; ruts form and persist; vehicles sink, spin and can get stuck for physical reasons; the winch recovers a stuck vehicle; fuel works; water fording works; the proving ground and the main map are accessible; the debug menu works; Blender assets import and display correctly; performance is acceptable for recording (target a stable 60 FPS, 30 FPS floor).

## 11.5 Asset-quality gate

Visually inspect the game and reject unintentional placeholder content. Prioritize finished versions of: the player vehicles (with visible suspension), the terrain materials and mud look, water, trees/rocks/logs, camp structures, bridges and signs. Document anything left unfinished.

## 11.6 Required documents

- **`DEVELOPMENT.md`** — Unity version and packages, architecture, the mud/physics design (data layout, update rates, formulas, tuning parameters), vehicle data, controls, map layout, Blender workflow, build/run instructions, test results, known limitations.
- **`FEATURE_MATRIX.md`** — status table described above.
- **`RESEARCH_NOTES.md`** — the research and adopt/adapt/skip decisions.
- **`SONNET_5.5_FINAL_REPORT.md`** — what was built, what works, what is partial, known bugs, controls, vehicles, map routes, physics results, performance notes, and the metrics block from Section 15.

Make meaningful Git milestone commits (baseline, physics prototype, first vehicle, deformation, suspension, drivetrain, winch, world, objectives, polish, final). Never commit `Library/`, `Temp/`, `Obj/`, `Logs/`, `UserSettings/` or build outputs.

---

# 12. Priority order

This project is broad. Follow this order and **do not stop early**:

1. stable Unity project, compile loop through the CLI/batch mode, verified Blender MCP pipeline;
2. **physics prototype**: a flat test arena with a simple vehicle (primitive stand-ins allowed) and the ground-interaction system (sinkage, traction, spin-digging);
3. suspension and wheel model stable with a heavy vehicle on rough ground;
4. visible deformation (ruts, berms) with acceptable performance;
5. first polished Blender-authored vehicle with visible suspension, drivable;
6. drivetrain: gears/ranges, AWD, diff locks, fuel;
7. proving ground with test obstacles; automated drive tests;
8. water, current and buoyancy;
9. winch and recovery;
10. remaining vehicles, trailer and cargo;
11. the large map with route choices, readable terrain and landmarks;
12. weather (rain affecting wetness), time of day, lights;
13. HUD, map/compass, camera modes, audio;
14. objectives/scenarios;
15. debug menu polish, art and VFX polish pass;
16. final QA, performance pass and documentation.

A strong first milestone: one polished vehicle drives in the proving ground, sinks in mud, leaves ruts, can get stuck by spinning its wheels and can be pulled out by a winch.

---

# 13. Performance

- Heavy simulation only near the player's vehicles; distant ground is static.
- Mud/deformation updates are local, throttled, and use compact data (consider Burst/Jobs where it measurably helps).
- Avoid per-frame allocations and per-object update spam; pool particles and effects; use instancing for vegetation and props; sensible LODs and culling.
- Target a stable 60 FPS at recording settings; verify with the profiler or frame-time logging.

---

# 14. Save/load

Persist at least: current vehicle and its fuel/damage, position, time of day, weather/wetness, objective progress and settings. A basic mud-state snapshot (rut field) is a stretch goal.

---

# 15. Session timing, token accounting and API-equivalent cost — mandatory

These metrics will be shown in a YouTube video about Claude Sonnet 5.5. Measure **only this Claude Sonnet 5.5 Unity MudRunner project**. Do not include other sessions or projects, and **do not fabricate precision**.

## 15.1 Development time

At the very beginning, before substantial work:

1. read the current operating-system timestamp with its timezone;
2. create a unique run directory and save the start time to `.sonnet-5.5-mudrunner-runs/<run-id>/start_time.txt`;
3. keep that run ID and start time unchanged for the whole task.

After the final validation and report preparation, read the timestamp again and save it to `end_time.txt` in the same directory. Compute the elapsed wall-clock time. If work is resumed, append identifiable segments instead of overwriting the original start; report known pauses separately; never sum overlapping tool/subagent durations.

## 15.2 Tokens

Obtain real usage from the runtime in which you are actually running (session usage metadata exposed by the agent or host, a usage record of this exact session, or the permitted local usage log identified reliably by session ID, working directory and timestamps). Read only relevant usage metadata; do not copy credentials or unrelated conversations into the repository.

Use mutually exclusive categories (uncached input, cache-read, cache-write, output; thinking/reasoning tokens only if separately exposed). Do not subtract cache usage from an already-uncached count and do not double count. Deduplicate events by request/message identity. A missing counter is **unknown**, not zero. Do not estimate tokens from code size, asset size, tool-call counts or elapsed time. Identify delegated subagent work separately and record the actual model of each part. If exact usage cannot be obtained, write exactly: `Exact token usage unavailable from the accessible runtime.`

## 15.3 API-equivalent price

Compute the **token-only API-equivalent cost in USD** from the verified usage using the **official Anthropic pricing for the model you actually ran as** (Claude Sonnet 5.5; verify the model identifier exposed by the session), at standard API pricing, from `https://platform.claude.com/docs/en/about-claude/pricing`. Record the source URL, verification date and the formula used. This is a benchmark equivalent, not the user's subscription payment or credits. If usage, model identity or pricing cannot be verified, say so and give a clearly labeled partial figure or "unavailable".

---

# 16. Start now

Begin immediately:

1. record the start timestamp and run ID;
2. inspect the Unity project, editor version and Unity CLI;
3. verify the Blender MCP connection on `localhost:9891` and the master file;
4. research MudRunner/Spintires/SnowRunner and write `RESEARCH_NOTES.md`;
5. write the plan, prototype the mud physics first, then build the game autonomously.

Remember:

**This is an original MudRunner-style off-road simulation built on Unity 6 (URP, C#). The primary focus is the physics of the mud and of the vehicle suspension and wheels; the player must find a path through the mud so the vehicle does not get stuck.**

**Use only the verified Blender MCP connection on `localhost:9891` with `UnitySonnet5.5Mudrunner.blend` in the project folder, and use it actively for every important 3D asset.**

---

# 17. FINAL REQUEST — time, tokens and API-equivalent cost (do this last)

When the game, the documentation and all validation are finished, **calculate and report the following three numbers for this project**, following Section 15 exactly:

1. **Time spent on the project** — the wall-clock duration between the start timestamp you saved at the very beginning and a fresh end timestamp, as `HH:MM:SS` plus total minutes; report known pauses separately.
2. **Number of tokens** — real usage of this session (uncached input, cache-read, cache-write, output, thinking if separately exposed, and a deduplicated total), or the exact sentence `Exact token usage unavailable from the accessible runtime.`
3. **Price in API-equivalent US dollars** — the token-only cost from the verified usage at the official Claude Sonnet 5.5 API price, or an explicit statement that it is unavailable.

Put them into this block at the bottom of `SONNET_5.5_FINAL_REPORT.md` **and** state them in your final chat message, each marked as measured, estimated or unavailable:

```text
## Claude Sonnet 5.5 Unity MudRunner Session Metrics

Project: Unity 6 MudRunner-style off-road mud physics game
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
Blender port: 9891
Blender master file: UnitySonnet5.5Mudrunner.blend
Verified full path of master file:
Approximate number of major Blender assets created:
```
