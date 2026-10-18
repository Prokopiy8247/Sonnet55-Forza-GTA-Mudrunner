# Claude Sonnet 5.5 — Godot + Blender MCP GTA-Style Compact Open-World Benchmark

## Mission

You are the sole lead developer and technical artist of the **existing Godot project in the project folder currently opened in this Claude agent**.

Your task is to build the most complete and polished **GTA-style single-player open-world sandbox** you can achieve during this autonomous development session.

This is **not** a mission/story game. There must be **no campaign, no quests, no mission markers, no scripted story missions, and no progression gated behind missions**.

The game should launch directly into **free roam** and focus on emergent sandbox gameplay:
- exploring a compact open world on foot;
- stealing/entering/driving vehicles;
- cars, motorcycles, boats, helicopters and airplanes;
- using many weapon types;
- fighting NPCs and police;
- committing crimes that escalate a wanted/pursuit system;
- interacting with shops and useful world locations;
- swimming;
- vehicle damage and explosions;
- traffic and pedestrians;
- day/night and weather;
- unrestricted sandbox experimentation.

The experience should reproduce as many of the **general open-world sandbox capabilities associated with games such as GTA V** as practical, while being an **original game**.

Use **GTA V single-player as a mechanics/sandbox-interaction reference only**. Do not use it as an art-direction requirement. Do not copy GTA/RDR maps, code, missions, characters, names, logos, textures, audio, UI artwork, story content, proprietary assets, or ripped game files.

The final game must be an original project.

## Godot implementation target

Use the existing **Godot 4.x** project and the exact installed stable Godot version detected on this machine.

Known environment (verify, do not blindly trust):

- The project in the current folder is named `Sonnet5.5GTA` and is already configured for **Godot 4.7**, **Forward Plus**, **Jolt Physics** (`3d/physics_engine`) and the `d3d12` rendering driver on Windows.
- A Godot 4.7.2 stable editor is installed at `W:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe`; the console build for headless/CLI validation is `W:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe`.
- Git is installed and on `PATH` (`W:\Git\Git\cmd\git.exe`).

Technical defaults:

- **GDScript** as the primary gameplay/tooling language.
- **Forward+** renderer is preferred for this desktop benchmark; it does not prescribe the visual style chosen in Section 5.
- `CharacterBody3D` for the player and suitable character controllers.
- `RigidBody3D` / custom physics for vehicles and physical props where appropriate.
- `NavigationRegion3D`, `NavigationMesh`, `NavigationAgent3D`, and `NavigationServer3D` for navigation/AI where useful.
- `.tscn` / `PackedScene` for reusable scenes.
- custom `Resource` / `.tres` data assets and data-driven registries where useful.
- `@tool`, EditorPlugin, EditorScript-style workflows and headless scripts for reproducible editor automation.
- `Control`/`Container`/Theme systems for UI.
- `AnimationPlayer`, `AnimationTree`, Skeleton3D and procedural animation/IK where appropriate.
- `MultiMeshInstance3D`, visibility ranges, occlusion, streaming and pooling where they improve dense-scene performance.

Do not require C#/.NET unless the existing project is already intentionally configured around it and using it is clearly more reliable. Prefer GDScript for this benchmark.

---

# 0. Existing project and mandatory Blender connection

Work directly in the current Godot project containing `project.godot`. **Do not create another nested Godot project.**

The user has already opened this project's folder in the current Claude agent and placed **`GodotSonnet5.5GTA.blend` in that folder**. Resolve the actual full working-directory path; do not import a project path or connection assignment from an earlier benchmark.

```text
Working folder: the current project folder opened in this Claude agent
Blender host: localhost
Blender port: 9890
Master Blender file: ./GodotSonnet5.5GTA.blend
MCP server name: expected to be `blender-godot` (declared in this project's .mcp.json) - still discover and verify the actual enabled connection for this endpoint
```

This is the **Claude Sonnet 5.5 Godot GTA benchmark**. The game scope, approximately 600×600 m ground footprint, unrestricted art-direction choice and prohibition on missions remain as specified below. Work only in this assigned project.

The Blender scene is expected to be an empty default scene at the start (another agent has already confirmed the connection and found only the default cube/camera/light). Everything described in this prompt still has to be created by you.

## Critical Blender routing rule

The user specified the **port and file**. This project's `.mcp.json` declares a server named `blender-godot` that launches `mcp-for-blender --port 9890`, but you must still confirm the real tool namespace exposed in this session. Choose the actual MCP connection exposed to this agent that is configured for **`localhost:9890`**. Determine its identity from available tool descriptions and relevant permitted connection configuration. Do not invent a server name or reuse an old name merely because it includes an engine's name.

If the agent is launched through a host application, use the tools actually enabled for this session. Do not assume that one standalone client's configuration file is the complete list of host-managed connections. Do not change global settings, register new servers or reconfigure another project's endpoint automatically.

Before making any Blender changes:

1. Record the session start time as described in Section 58 and resolve the current project directory.
2. Confirm that `GodotSonnet5.5GTA.blend` exists in that directory.
3. Identify the available MCP connection configured for `localhost:9890`.
4. Execute a real read-only Blender MCP call. Inspect the opened scene and obtain the full path of its current `.blend` through an available permitted read-only operation.
5. Confirm that this path is the exact `GodotSonnet5.5GTA.blend` in the assigned project folder. A listening port, a process ID or a matching basename alone is not confirmation of access to the intended scene.
6. Back up the existing master file before its first modification. Record the verified server/tool namespace, endpoint and full file path in `DEVELOPMENT.md` and the final report.

For every subsequent Blender operation:

- use **only this verified connection on port 9890**;
- use **`GodotSonnet5.5GTA.blend` in the current project folder** as the canonical editable source;
- do not modify scenes, files or MCP connections belonging to any other project;
- preserve existing unrelated collections, meshes, materials and unsaved user work;
- organize this project's generated assets in clearly named collections;
- save the master file regularly under the same name and path;
- keep exports and technical backup copies separate from the canonical source.

If the required MCP tools are unavailable, an actual tool call fails or the opened file does not match, report the exact blocker and the minimum correction needed. Do not write to another Blender instance, silently replace Blender-authored assets with engine primitives, or claim a successful MCP verification. Independent project inspection/planning can continue safely, but the mandatory Blender pipeline cannot be marked complete until it really works.

## Blender permissions and automation

Respect the permissions and Safe Mode of the installed MCP connector. Use its available structured tools or permitted Blender-native operations. Reusable `bpy` scripts actually executed through the approved MCP connection and checked in the scene are allowed; merely writing an unexecuted script is not asset creation.

Do not disable safeguards, patch the add-on, bypass validation or silently switch to an unrestricted Blender process. Do not make the user perform routine modeling, export, import or component wiring that the permitted tools can automate.

Additional source `.blend` files or automatic backups are allowed only when needed for stability; **`GodotSonnet5.5GTA.blend` remains the master file for this benchmark**.

---

# 1. Blender MCP is mandatory

Blender MCP is a **required active part of the 3D asset-production pipeline**, not an optional extra.

Use the verified Blender MCP connection defined in Section 0 actively to:

- inspect the Blender scene;
- create meshes;
- edit geometry;
- create UVs;
- create materials;
- build rigs where useful;
- create basic animations where practical;
- position pivots/origins correctly;
- prepare LOD-friendly geometry;
- create collision helper meshes when useful;
- create render/viewport previews;
- inspect visible results;
- revise poor-looking assets;
- save source Blender work;
- export engine-ready assets;
- integrate them into Godot.

Do not merely write Blender Python scripts and leave them unused if the MCP can perform and verify the operation directly.

Do not ask me to manually model, UV, rig, export, import, or wire important assets.

## Blender visual QA loop

For every important hero asset:

1. inspect the current Blender scene;
2. model or modify the asset through the verified Blender MCP connection defined in Section 0;
3. create appropriate materials/UVs;
4. inspect it visually using Blender viewport/render feedback when available;
5. revise it if it looks visibly broken, incoherent, or placeholder-quality;
6. save the Blender source;
7. export it primarily as GLB/glTF 2.0, following Section 41; use FBX only when the installed Godot version and the particular asset validate more reliably with it;
8. import it into Godot;
9. configure materials, colliders, physics and gameplay components;
10. test it in the actual game.

A Blender asset is **not finished merely because a file exists**. It must work and look reasonable inside Godot.

---

# 2. No external asset shortcuts

This benchmark is about **Claude Sonnet 5.5 + Godot + Blender MCP**.

Do not depend on:
- Godot Asset Library packs;
- ripped GTA assets;
- Sketchfab;
- Poly Haven downloaded asset packs;
- Poly Pizza;
- Meshy;
- Rodin;
- Hunyuan 3D;
- external 3D generation services;
- copyrighted commercial asset packs;
- downloaded character/vehicle/weapon models.

Create the important project-specific 3D assets yourself with Blender MCP and project-owned code.

Built-in Godot functionality, engine modules, and project-owned scripts/resources are allowed.

Procedurally generated project-owned textures, materials, meshes and audio are allowed.

---

# 3. Autonomy and workflow

I am a Godot beginner.

Do **not** expect me to manually:
- create scenes/nodes manually;
- assemble `.tscn` scenes/PackedScenes manually;
- assign Inspector references manually;
- set up render settings;
- build UI;
- create materials;
- rig vehicles;
- configure weapons;
- set up NavigationRegion3D/NavigationMesh manually;
- create traffic routes;
- set up Blender exports;
- repair compile errors.

Take ownership of the implementation.

Read this entire prompt and applicable local project instructions such as `CLAUDE.md` or `AGENTS.md`. Record the start timestamp immediately as described in Section 58.

Before substantial work:

1. inspect the entire Godot project and `project.godot`;
2. detect the exact installed Godot version and renderer;
3. identify the current render pipeline;
4. identify installed packages;
5. inspect the existing `GodotSonnet5.5GTA.blend`;
6. confirm access to the verified Blender MCP connection defined in Section 0;
7. create a concise technical plan;
8. create/update `.gitignore`;
9. initialize Git and create a baseline commit if Git is available and the project is not already under version control;
10. create:
   - `DEVELOPMENT.md`
   - `FEATURE_MATRIX.md`
   - `SONNET_5.5_FINAL_REPORT.md`
11. preserve the original start timestamp and run ID recorded before this inspection.

Then work autonomously.

Do not stop and ask for confirmation after each subsystem.

If one feature becomes a deep blocker:
- preserve the working game;
- document the limitation;
- move to another high-value feature;
- return later if possible.

Do not claim an unfinished feature is working.

---

# 4. Overall design target

Create an original modern urban/crime open-world sandbox with:

- visual style chosen autonomously by Claude Sonnet 5.5;
- third-person character control;
- optional first-person mode if practical;
- compact but dense open-world map of approximately 600×600 meters;
- varied urban and natural environments consistent with the chosen art direction;
- dense traffic and pedestrians;
- drivable land, air and water vehicles;
- combat;
- police response;
- wanted levels;
- shops;
- garages;
- weapon inventory;
- vehicle ownership/spawning for testing;
- day/night;
- weather;
- dynamic world reactions;
- explosions;
- physics;
- free-roam sandbox tools.

There must be **no mission system**.

The default experience is:

```text
Launch game
→ load/open world
→ control player immediately
→ freely explore and cause/interact with sandbox systems
```

---

# 5. Art direction — intentionally unspecified

You decide the visual style of this project.

There is **no prescribed visual style or 3D-model style**.

Do not infer an art direction from the fact that the gameplay is GTA-style.

Choose the visual style, character design language, vehicle design language, environment treatment, materials, lighting approach and 3D-model style entirely yourself based on what you believe will produce the strongest cohesive result within the available development time.

Once you choose an art direction:

- apply it consistently across the player, NPCs, vehicles, weapons, buildings, props, UI, VFX and world;
- use Blender MCP actively for important authored 3D assets;
- avoid accidental placeholder content unless it is temporary during implementation;
- prioritize visual coherence, readability and a finished-looking result over any particular style.

The GTA V reference in this prompt is about **mechanics, sandbox interactions and feature scope**, not about copying or imitating its graphics.
---

# 6. Renderer and visual pipeline

Inspect the existing Godot project first.

Forward+ is preferred for this desktop benchmark when it is already configured and stable, but **do not infer a visual style from the renderer choice**.

Use Godot 4 rendering features as appropriate for the art direction you choose:
- `WorldEnvironment` / `Environment`;
- `DirectionalLight3D`;
- fog;
- SSAO / SSIL / GI features where useful;
- ReflectionProbe;
- Decal nodes;
- shadows;
- tonemapping/post effects;
- emissive materials;
- sky/atmosphere;
- water shaders.

Use only the rendering features that serve the art direction you choose.
---

# 7. Compact open-world map — fixed target size

The playable map footprint should be approximately:

```text
600 m × 600 m
≈ 0.6 km × 0.6 km
≈ 0.36 km²
≈ 36 hectares
```

Treat this as a deliberate benchmark constraint.

Do **not** build an enormous open world and do not spend the session expanding the playable ground map beyond this approximate footprint.

The goal is to fit as much GTA-style sandbox density and mechanical variety as possible into a compact map.

## Map composition

Create a dense, varied map with several clearly distinguishable districts/areas inside the 600×600 m footprint.

Prioritize a compact combination of:

1. **Downtown / commercial core**
   - taller buildings;
   - shops;
   - intersections;
   - alleys;
   - parking;
   - traffic lights.

2. **Residential area**
   - houses/apartments;
   - smaller roads;
   - yards or courtyards;
   - a park or public space.

3. **Industrial / service area**
   - warehouse/factory-style buildings;
   - storage/service yards;
   - utility props;
   - garage/repair access.

4. **Waterfront / dock / beach edge**
   - enough water for swimming and boats;
   - piers/docks;
   - coastal road or promenade.

5. **Green / elevated area**
   - park, hillside, wooded area or other non-urban contrast;
   - paths and a viewpoint where practical.

6. **Compact aviation area**
   - helipad;
   - small airstrip/runway or equivalent test area if practical;
   - enough access to demonstrate helicopters and airplanes;
   - aircraft mechanics remain required even though the ground map is compact.
   - Aircraft may briefly fly beyond the main 600×600 m ground footprint over simplified/non-playable surroundings if needed for takeoff, landing and turning room, but do not expand the detailed playable ground map just for aviation.

7. **Road network**
   - interconnected roads;
   - at least one faster arterial/highway-like stretch;
   - intersections suitable for traffic and police pursuits;
   - route loops that make chases useful within the compact footprint.

Fit useful world locations into the same map where practical:
- police station;
- hospital/respawn point;
- weapon shop;
- vehicle customization/repair garage;
- safehouse;
- gas/service station;
- parking/vehicle access;
- clothing/appearance locations if implemented.

The world must be original and must not recreate Los Santos or any real GTA map.

Favor **density and interaction variety** over geographic scale.
---

# 8. Compact-world performance and simulation

The map is intentionally about 600×600 meters, so do not build heavyweight huge-world infrastructure merely for scale.

Still design the project to remain efficient with traffic, pedestrians, police, vehicles, wildlife, VFX, physics, interiors and shops.

Use sensible techniques available in the current engine, such as:
- pooling;
- distance-based AI update rates;
- LOD / visibility ranges / HLOD or equivalent when useful;
- occlusion/frustum culling;
- instancing for repeated props/vegetation;
- local activation/deactivation of expensive systems;
- spawn/despawn management around the player.

Sectoring/streaming may still be used if it simplifies organization or improves performance, but it is **not** a goal by itself.

Do not implement floating-origin systems or other huge-world infrastructure unless a real technical need appears.

The game should remain stable and suitable for screen recording.
---

# 9. Environment asset pipeline

Use Blender MCP to create **modular environment kits consistent with the art direction you choose** rather than individually hand-modeling every building from scratch.

Create reusable Blender collections/assets for:

### Buildings
- modern office façade modules;
- apartment modules;
- suburban house kit;
- storefront modules;
- industrial warehouse kit;
- airport/hangar kit;
- garage/parking structures.

### Street assets
- traffic lights;
- street lamps;
- traffic signs;
- barriers;
- benches;
- bins;
- fire hydrants;
- bus stops;
- fences;
- utility boxes;
- bollards;
- road cones.

### Roads
Use Godot tooling/code (for example `@tool` scripts, `Path3D`/`Curve3D`, and generated meshes) for road layout where more efficient, but create necessary visual assets through Blender:
- curbs;
- barriers;
- signs;
- lamp posts;
- road furniture.

Use project-generated materials/decals for:
- asphalt;
- lane markings;
- dirt;
- oil;
- cracks;
- crosswalks;
- sidewalks.

### Nature
Create/use project-owned:
- trees;
- bushes;
- rocks;
- grass;
- roadside vegetation.

Prioritize coherent silhouettes, reusable assets and sensible LODs.

---

# 10. Player character

Default gameplay should be **third-person**, similar to modern open-world action games.

For Godot, prefer a robust `CharacterBody3D`-based player controller with a separate camera rig/pivot. Use `SpringArm3D` or an equivalent custom collision-aware camera solution where it produces stable results.

Implement:
- walk;
- run;
- sprint;
- jump;
- crouch if practical;
- aim;
- shooting;
- melee;
- weapon switching;
- entering/exiting vehicles;
- swimming;
- falling;
- ragdoll/death;
- camera orbit;
- camera collision;
- shoulder aiming;
- smooth movement transitions.

Optional/high priority:
- first-person mode toggle.

## Character model

Use Blender MCP to create an original player character in the visual style you choose for the project.

Do not leave the final player as an accidental engine placeholder unless that appearance is an intentional authored part of the chosen art direction.

Create the body, clothing/accessories and articulation appropriate to your chosen style.

Rig it for gameplay.

Use the current engine's character/skeleton/animation systems appropriately.

If fully bespoke animation is too expensive, prefer procedural animation, IK, reusable animation layers and carefully authored simple motion over visibly broken animation.

---


# 10A. Cover, stealth, traversal and close-combat depth

GTA V's on-foot sandbox is not only running and shooting. Build a more complete action-game movement/combat layer.

## Cover system — high priority

Implement a contextual cover system that works with common world geometry:

- enter/exit cover near suitable walls, barriers, vehicles and low objects;
- standing and low-cover poses;
- move left/right while attached to cover;
- peek around corners and over low cover;
- aim out from cover;
- fire from cover;
- blind fire with reduced accuracy;
- move around compatible cover corners;
- smoothly leave cover when movement demands it;
- avoid camera clipping while in cover.

Police and hostile AI should also use cover where practical.

## Stealth mode

Implement a GTA-like stealth state:

- slower/quieter movement;
- reduced footstep/noise radius;
- lower detection likelihood when out of sight;
- stealth takedown from behind;
- suppressed weapons interact with detection/noise;
- NPC suspicion/detection should depend on line of sight, distance, noise and obvious hostile behavior.

Stealth should remain a sandbox option and must not create stealth missions.

## Traversal

Improve basic traversal with:

- jump;
- climb/vault over low obstacles;
- contextual mantle where practical;
- ladder climbing;
- dodge/roll while aiming if practical;
- fall/landing reactions;
- ragdoll when impact thresholds are exceeded.

Do not turn traversal into parkour. Keep it grounded and GTA-like.

## Melee

Expand melee beyond a single attack:

- light/standard strike;
- heavier strike or contextual finisher;
- block/dodge where practical;
- melee weapon support;
- knockdown;
- different reactions based on attack direction/strength.

---

# 11. NPC population

Create a living population system.

NPC types should include:
- ordinary pedestrians;
- drivers;
- police officers;
- armed police/tactical units;
- shop staff;
- optional criminals/gang-like hostile NPCs.

NPCs should:
- walk around;
- use sidewalks;
- cross roads where practical;
- react to traffic;
- react to collisions;
- panic when gunfire/explosions occur;
- flee from danger;
- call/react to police events where practical;
- drive vehicles;
- fight or defend themselves depending on type;
- ragdoll or react physically to impacts;
- despawn/respawn intelligently for performance.

Create multiple visual variants through Blender:
- male/female body variations;
- clothing variations;
- skin/hair variations;
- police uniforms;
- tactical variants.

Do not make every NPC visually identical.

---

# 12. Traffic system

The city should contain believable civilian traffic.

For pedestrians, use Godot navigation (`NavigationRegion3D`, `NavigationAgent3D`, NavigationServer3D) where useful. Vehicle traffic should primarily follow a project-owned lane/road graph rather than forcing car AI onto pedestrian navigation meshes.

Implement:
- road graph / lanes;
- intersections;
- traffic signals;
- traffic direction;
- vehicle following;
- stopping;
- basic collision avoidance;
- lane changes where practical;
- traffic density scaling;
- vehicle spawn/despawn around player;
- parked vehicles;
- honking/reaction hooks;
- accidents and stopped traffic handling where practical.

Traffic AI does not need perfect real-world autonomy, but should look believable during normal driving.

---

# 13. Vehicle system

Vehicles are a major headline feature.

Implement a reusable vehicle framework with:
- enter/exit;
- driver seat;
- camera;
- steering;
- throttle;
- brakes;
- reverse;
- handbrake;
- suspension;
- tire grip;
- speed;
- engine state;
- damage;
- collision;
- headlights;
- brake lights;
- engine audio hooks;
- horn;
- vehicle health;
- explosions/fire when heavily damaged if practical.

Use a reliable Godot vehicle solution: preferably a project-owned `RigidBody3D`-based vehicle with raycast/custom suspension and wheel forces, or `VehicleBody3D`/`VehicleWheel3D` if testing shows they are suitable and stable for this project.

## Vehicle classes

Create multiple distinct Blender-authored vehicles.

Minimum high-priority set:

### Cars
- compact car;
- sedan;
- sports car;
- muscle car;
- SUV;
- pickup;
- van;
- police cruiser.

### Two-wheel
- motorcycle;
- bicycle if practical.

### Water
- speedboat or motorboat.

### Air
- civilian helicopter;
- police helicopter;
- small propeller airplane;
- jet or fast airplane as stretch.

### Additional stretch
- truck;
- taxi;
- ambulance;
- fire truck;
- armored/police tactical vehicle.

Do not simply scale the same mesh to fake every vehicle category.

Use distinct silhouettes and handling profiles.

---


# 13A. Carjacking, drive-by combat and vehicle interaction

Vehicle gameplay must include the interactions that make a GTA-style sandbox feel complete.

## Carjacking

Support:

- entering an empty vehicle normally;
- pulling a civilian driver out of an occupied vehicle;
- NPC driver reaction/panic/fight-back depending on personality;
- theft of an occupied vehicle counting as a crime when witnessed;
- police vehicle theft causing an immediate serious response;
- motorcycles/bicycles using suitable contextual enter/steal animations.

The system may use simplified procedural transitions if full authored animations are not feasible, but it should not feel like instant teleportation when a visible character is in the seat.

## Drive-by shooting

Allow context-appropriate weapons while driving/riding:

- pistols;
- compact SMG-type weapons;
- throwable explosives where implemented;
- suitable one-handed weapons.

Implement:

- free aim from vehicle;
- camera support while aiming;
- reduced accuracy compared with standing fire;
- driver weapon restrictions;
- motorcycle forward/side firing;
- AI police/hostile drivers or passengers using vehicle weapons when appropriate.

## Vehicle detail interactions

Where practical support:

- headlights;
- high/low lights or simple toggle;
- brake lights;
- reverse lights;
- horn;
- siren for emergency vehicles;
- convertible roof on compatible cars;
- doors opening/closing;
- trunk/hood interaction as stretch;
- seat-specific entry points.

---

# 14. Vehicle Blender requirements

Major vehicles must be authored through the verified Blender MCP connection defined in Section 0.

You decide the vehicle modeling style.

For each important vehicle, create the components required by the gameplay and chosen art direction, such as:
- body;
- wheels;
- lights;
- visible cabin/interior elements when useful;
- steering wheel where visible;
- separate wheel objects;
- correctly placed pivots/origins;
- appropriate scale;
- material slots;
- collision-friendly structure.

Create distinct silhouettes for different vehicle classes instead of only resizing one mesh.

Materials, geometry detail, proportions and surface treatment should follow the art direction you choose.

Create LOD-friendly or otherwise performance-conscious geometry where practical.

---


# 14A. Vehicle customization and repair shop — high priority

Create an original in-world vehicle modification/repair garage inspired by the general functionality of GTA V's car customization system.

It must not copy Los Santos Customs branding, UI, logos or shop design.

The player should be able to drive a compatible vehicle into the shop and:

## Repair
- restore vehicle health;
- repair broken glass/lights where represented;
- restore handling damage.

## Cosmetic customization
Support as many as practical:

- primary paint;
- secondary paint;
- gloss/matte/metallic-style finishes;
- wheels/rims;
- wheel color;
- window tint;
- bumpers;
- hood;
- roof options;
- grille;
- exhaust;
- skirts;
- spoiler;
- lights;
- horn;
- license plate style;
- optional livery/stripe variants.

## Performance customization
Make upgrades genuinely affect handling/performance:

- engine tuning;
- brakes;
- suspension;
- transmission;
- turbo/forced-induction-like upgrade;
- armor;
- tire durability / bullet-resistant tire option;
- spoiler/downforce tuning where appropriate.

Use data-driven upgrade definitions.

Visual body modifications should use Blender-authored modular parts or carefully designed mesh variants rather than simply changing scale.

The benchmark/debug menu may unlock everything immediately, but normal free-roam purchases should cost in-game money.

---

# 15. Aircraft and helicopter gameplay

## Helicopters

Implement:
- takeoff/landing;
- collective/lift;
- yaw;
- pitch/roll;
- forward flight;
- responsive arcade-realistic controls;
- third-person chase camera;
- damage/crash.

## Airplanes

Implement:
- throttle;
- takeoff;
- pitch;
- roll;
- yaw;
- stall/low-speed degradation at least approximately;
- landing;
- crash/damage.

Controls can be accessible/arcade-like rather than flight-simulator complex.

Airport runways must support meaningful flight gameplay.

---

# 16. Boats and swimming

Implement:
- swimmable water;
- player buoyancy/swim controls;
- drowning/health consequences if useful;
- boats with buoyancy-like motion;
- entering/exiting boats;
- coastal/port gameplay.

Water should visually fit the art direction you choose.

---

# 17. Weapons and combat

Create a substantial weapon system.

High-priority weapon categories:

### Melee
- fists;
- knife or melee weapon;
- bat/crowbar-like weapon.

### Handguns
- pistol;
- heavy pistol/revolver-like variant.

### SMG
- compact SMG.

### Shotguns
- pump shotgun;
- optional semi-auto shotgun.

### Rifles
- assault rifle;
- carbine;
- marksman rifle.

### Sniper
- sniper rifle with scoped aiming.

### Heavy/explosive
- grenade;
- rocket launcher;
- optional grenade launcher.

Do not copy GTA weapon models or brand names.

Use original generic weapon designs.

## Weapon behavior

Implement:
- weapon equip;
- weapon wheel or fast selection;
- ammo;
- magazines;
- reload;
- recoil;
- bullet spread;
- fire rate;
- hitscan/projectiles as appropriate;
- muzzle flash;
- shell/effect hooks;
- hit reactions;
- headshot/damage zones where practical;
- explosions;
- camera shake;
- aim zoom;
- scoped view for sniper.

Use Blender MCP to create proper 3D weapon models.

Do not use primitive cubes as final guns.

---


# 17A. Weapon customization and combat presentation

Create a weapon modification layer for compatible firearms.

At an original weapon shop/workbench, allow combinations such as:

- extended magazines;
- suppressor;
- flashlight;
- optic/scope;
- grip/stability upgrade where appropriate;
- cosmetic finish/tint;
- optional higher-capacity magazine for selected weapons.

Modifications must have actual gameplay effects when relevant:

- suppressor reduces audible detection radius but may slightly affect weapon balance;
- scope changes aiming/FOV;
- grip reduces recoil/spread;
- extended magazine increases capacity;
- flashlight illuminates dark environments while aiming.

## Ballistic interaction

Add practical material response:

- sparks on metal;
- dust/chips on concrete;
- glass breaking;
- decals or impact marks where performant;
- different impact audio hooks.

Stretch:
- limited penetration through thin materials;
- tire puncture from bullets;
- vehicle glass damage.

---

# 18. Police and wanted system — mandatory

This is one of the most important systems.

Implement a **0–5 level wanted/pursuit system**.

The player begins at:

```text
0 stars
```

Crimes increase wanted pressure.

Possible crime sources:
- attacking civilians;
- killing NPCs;
- shooting in public;
- attacking police;
- stealing occupied vehicles;
- major collisions;
- explosions;
- destroying police vehicles;
- continued resistance/arrests avoided.

Use witnesses/visibility where practical so not every crime instantly becomes globally known.

## Wanted levels

### 1 star
- nearby patrol responds;
- officers pursue/investigate.

### 2 stars
- more police cars;
- more aggressive pursuit;
- armed response.

### 3 stars
- larger vehicle response;
- roadblocks;
- police helicopter/search support if practical.

### 4 stars
- tactical/heavily armed units;
- stronger roadblocks;
- aggressive helicopter support.

### 5 stars
- maximum pursuit;
- many units;
- tactical vehicles/teams;
- sustained air support;
- difficult escape.

The exact numbers can be tuned for playability.

## Search / escape behavior

The wanted system should not simply be a timer.

Implement:
- police line of sight;
- last-known position;
- search radius/area;
- pursuing state;
- searching state;
- cooldown;
- stars decay when player remains unseen long enough.

Changing vehicle or hiding should help if police genuinely lose visual contact.

HUD must clearly show wanted level.

---


# 18A. Wanted-system refinements from GTA-style free roam

Strengthen the wanted system beyond simple star accumulation.

## Witnesses

Crimes should not always instantly become magically known.

When practical:

- civilians who directly witness a serious crime may panic and call police;
- if the player stops/escapes before a report completes, response may be delayed or prevented;
- gunshots/explosions can create an indirect report radius;
- police who directly see the crime report it immediately.

Do not make this system so complex that it destabilizes core police response.

## Active pursuit vs search state

Clearly separate:

### Pursuit
Police currently see/track the player.

### Search
Police have lost direct sight and search based on last known location.

During Search:
- wanted stars flash or otherwise visually communicate loss of direct contact;
- minimap shows nearby police/search directions or cones when practical;
- entering a police line of sight immediately resumes pursuit;
- escape timer progresses only while genuinely unseen.

Higher wanted levels should require a longer successful escape.

## Police vehicle tactics

Add GTA-like pursuit tactics where practical:

- PIT maneuver attempts;
- boxing-in at low speed;
- ramming from suitable angles;
- roadblocks at higher levels;
- spike strips as stretch;
- officers commandeering nearby civilian vehicles if stranded as stretch.

## Appearance / vehicle changes

During Search, changing obvious appearance or abandoning a clearly identified vehicle may slightly help the player evade detection.

Do not make it an instant universal wanted-clear button.

## Busted state

Police do not always need to kill the player.

If the player is:
- unarmed/not actively resisting;
- cornered at close range;
- or otherwise in an arrestable state,

allow a simplified **BUSTED/arrest** outcome.

On arrest:
- fade/respawn;
- clear wanted level;
- apply a modest money/ammo penalty if desired.

This should coexist with the death/respawn system.

---

# 19. Police AI

Police should:
- investigate crimes;
- pursue player;
- use vehicles;
- exit vehicles;
- aim/shoot when escalation warrants it;
- seek nearby positions/cover approximately;
- call/spawn reinforcements;
- create roadblocks at higher wanted levels;
- use helicopter support where implemented;
- attempt to surround/intercept rather than only drive directly into the player.

Do not spawn police directly in the player's visible field of view if avoidable.

---

# 20. Combat AI

Hostile NPCs should support:
- target selection;
- line of sight;
- firing;
- reloading;
- movement;
- basic cover use if practical;
- flanking/position changes as stretch;
- melee at close range where appropriate;
- death/ragdoll;
- surrender/fleeing behavior for civilians.

The player's combat should remain responsive even with many AI actors nearby.

---

# 21. Physics and reactions

Use physics to create convincing sandbox interactions.

Implement where practical:
- ragdolls;
- vehicle impacts;
- destructible light props;
- movable street objects;
- explosions applying force;
- NPC knockdown;
- vehicle-to-NPC impact reactions;
- damaged vehicle handling;
- broken street furniture;
- fire/explosion chain reactions for vehicles.

Do not attempt expensive full-building destruction if it compromises the project.

---

# 22. Vehicle damage

Vehicles should visibly and mechanically react to damage.

At minimum:
- health/durability;
- collision damage;
- smoke at heavy damage;
- fire before destruction if practical;
- eventual explosion/destruction;
- damaged handling.

Stretch:
- detachable doors/hood;
- broken glass;
- damaged lights;
- wheel damage;
- limited deformation.

A simple but convincing damage model is better than unstable full soft-body simulation.

---

# 23. World interactions

The player should be able to interact with the sandbox beyond shooting/driving.

High-priority:
- enter/exit vehicles;
- steal occupied vehicles;
- pick up weapons/ammo;
- buy/get weapons;
- use shops;
- interact with doors/use points;
- use garages/vehicle spawn points;
- swim;
- climb simple ladders if practical;
- use elevators/automatic doors where useful.

Optional:
- basic clothing change;
- vehicle repair;
- body armor purchase;
- food/health purchase.

No missions or quests.

---


# 23A. Player customization, safehouses, phone and personal services

Add free-roam identity/lifestyle systems that make the world feel closer to a complete GTA-style sandbox.

## Clothing

Create original clothing stores or wardrobe interaction with a modest but visible set of:

- shirts/jackets;
- pants;
- shoes;
- hats;
- glasses/accessories.

Use Blender-authored modular clothing or material variants where practical.

Clothing is cosmetic and must not become a mission requirement.

## Hair / appearance

Add a barber/salon-like interaction as stretch:

- hair variants;
- facial-hair variants;
- simple appearance options.

A tattoo shop is a lower-priority stretch feature.

## Safehouse

Provide at least one usable safehouse/home with:

- save/respawn role;
- wardrobe access;
- garage access;
- optional sleep/time-skip;
- basic interior.

## Garages / stored vehicles

Support storing a small set of player-selected vehicles persistently.

A stored/personal vehicle should be retrievable after loading when practical.

## Smartphone / interaction device

Create an original in-game phone or interaction interface for free-roam utility.

Useful functions may include:

- contacts/services;
- call/request taxi;
- camera/photo mode;
- quick save;
- vehicle/garage service;
- basic map/waypoint access.

Do not recreate GTA's exact phone UI or brands.

---

# 24. Economy and shops

Implement a lightweight free-roam economy.

Player has:
- cash balance;
- weapon shop purchases;
- ammo purchases;
- armor/health purchases where appropriate;
- vehicle repair or garage costs if implemented.

Because there are no missions, provide multiple sandbox-compatible ways to obtain/test money:
- initial reasonable cash;
- NPC cash drops where appropriate;
- pickups;
- debug/cheat controls;
- optional store robbery/emergent crime interaction as stretch.

Do not make economy grind block testing.

---

# 25. Weapon shop

Create at least one interactable weapon store.

It should allow buying:
- handguns;
- SMGs;
- shotguns;
- rifles;
- ammo;
- armor if implemented.

Use an original store identity and original UI.

---

# 26. Garage / vehicle access

Provide a convenient way to access vehicles for free-roam testing.

Possible implementations:
- garages;
- parking lots;
- dealership;
- debug/admin spawn menu.

The player must not be forced to search the whole map just to demonstrate a helicopter or airplane.

---

# 27. Day/night cycle

Implement:
- time-of-day cycle;
- sunrise;
- daylight;
- sunset;
- night;
- street lights;
- vehicle headlights;
- building/window lighting where practical;
- nighttime traffic/pedestrian variation if practical.

Visual quality at night matters.

---

# 28. Weather

Implement several weather states:

- clear;
- cloudy;
- rain;
- fog;
- storm if practical.

Weather should affect presentation:
- sky;
- lighting;
- wet-looking surfaces if possible;
- visibility;
- rain particles;
- reflections where supported.

Stretch:
- reduced vehicle grip in rain.

---

# 29. Map navigation

Implement a useful minimap/HUD navigation system.

At minimum:
- minimap or radar;
- player heading;
- roads or simplified map representation;
- police/wanted feedback;
- major world locations.

Stretch:
- full-screen map;
- waypoint;
- simple GPS route line.

No mission markers.

---


# 29A. Public transport, parachuting, underwater exploration and wildlife

These systems are high-value free-roam mechanics because they make the map feel like a world rather than a combat arena.

## Taxi passenger service

Allow the player to:

- hail/call a taxi;
- enter as a passenger;
- choose a map destination;
- ride there normally;
- optionally skip/fast-forward the trip after a short transition.

Taxi driving as a paid side activity is optional and should remain a free-roam activity, not a mission chain.

## Trains / transit

If technically practical, include:

- moving trains and/or subway;
- player can board/ride at least one transit type;
- trains follow fixed routes;
- collisions are handled safely.

## Parachute

Implement a usable parachute system:

- equip automatically or from inventory when available;
- deploy after jumping/falling;
- steer;
- descend;
- flare/slow for landing;
- landing damage for bad landings;
- altimeter while parachuting if useful.

Place parachutes at suitable high locations and/or aircraft so free-roam jumps are easy to test.

## Underwater / diving

Expand swimming with:

- diving below surface;
- breath/lung capacity;
- underwater camera/fog/audio treatment;
- deeper coastal areas;
- underwater props/wreck-like exploration areas;
- optional scuba gear that enables much longer underwater exploration.

## Wildlife

Populate suitable non-urban regions with a limited but convincing wildlife system.

Examples:
- deer;
- coyotes;
- boar;
- rabbits;
- birds;
- farm animals;
- dogs/cats;
- fish;
- sharks or another dangerous marine animal.

Animals should use simple ecosystem-appropriate behavior:
- grazing/wandering;
- fleeing;
- predators attacking only where appropriate;
- aquatic movement;
- region-based spawning.

Keep counts performance-conscious.

---

# 30. HUD

Create a polished GTA-like-but-original HUD.

Implement UI with Godot `CanvasLayer`, `Control`, Container nodes, Themes and custom draw/shader resources where useful. Avoid fragile pixel-positioned UI when a responsive container layout is more appropriate.

Display as appropriate:
- health;
- armor;
- ammo;
- selected weapon;
- wanted stars;
- money;
- minimap;
- vehicle speed;
- vehicle health indicator if useful.

Do not copy GTA V's exact HUD artwork.

Create an original modern interface.

---

# 31. Weapon wheel

Implement a weapon-selection interface inspired by the general radial-selection concept used in modern action games.

It may:
- slow time while open;
- organize weapon classes;
- show ammo;
- allow quick mouse/controller selection.

Do not copy exact GTA V artwork.

---

# 32. Camera

Third-person camera should feel polished.

Implement:
- smooth follow;
- orbit;
- collision avoidance;
- aim camera;
- vehicle chase camera;
- vehicle look-around;
- helicopter/plane chase camera;
- camera shake;
- field-of-view tuning.

Optional:
- first-person toggle for player and vehicles.

---

# 33. Controls

Create sensible default keyboard/mouse controls.

Suggested defaults:

```text
WASD             Move / vehicle control
Mouse            Camera / aim
Left Shift       Sprint
Space            Jump / handbrake in vehicle depending context
Ctrl/C           Crouch if implemented
F                Enter/exit vehicle
Left Mouse       Fire / melee attack
Right Mouse      Aim
R                Reload
1-9 / wheel      Weapon selection
Tab              Weapon wheel
E                Interact
M                Map
Esc              Pause
V                Camera toggle
H                Horn where context-appropriate
```

Use context-sensitive controls where practical.

Add controller support only after keyboard/mouse is stable.

---

# 34. Audio

Do not use copyrighted GTA/RDR audio or music.

Use Godot `AudioStreamPlayer`, `AudioStreamPlayer3D`, audio buses/effects, and generated/project-owned audio resources.

Create original/project-owned audio where practical:
- footsteps;
- gunshots;
- reloads;
- impacts;
- explosions;
- vehicle engines;
- tires/skids;
- horn;
- sirens;
- helicopter;
- ambient city;
- ocean;
- rain;
- UI.

If suitable audio generation is not possible with available tools, create simple original procedural/synthesized audio rather than copying commercial assets.

Audio quality is important, but do not block gameplay progress on perfect sound design.

---

# 35. Vehicle audio

Vehicles should have convincing feedback:
- engine pitch by RPM/speed;
- acceleration;
- braking/skid;
- impact;
- horn;
- police sirens;
- helicopter rotor;
- airplane engine.

Procedurally generated audio is acceptable.

---


# 35A. Emergency-world response and ambient services

Make the sandbox react to incidents beyond only police.

Where practical:

- ambulances respond to serious NPC injuries/deaths;
- fire trucks respond to major fires/explosions;
- emergency vehicles use sirens and traffic attempts to yield;
- responders despawn intelligently when far from the player;
- tow/service vehicle behavior is a stretch feature.

These systems are atmospheric. Do not let them overwhelm performance or interfere with the wanted system.

## Radio / in-vehicle media

Create an original radio/media system as a stretch feature.

Requirements:
- station/channel selection wheel or cycling;
- vehicle audio source;
- original/project-owned music or procedural audio only;
- no copyrighted commercial tracks;
- remember last selected station when practical.

A simple set of distinct original ambient stations is enough for the benchmark.

---

# 36. World ambience

Add environmental life:
- distant city noise;
- vehicle sounds;
- ambient pedestrian chatter-like nonverbal noise where possible;
- wind;
- coastal ambience;
- rain;
- industrial ambience.

Do not use copyrighted recordings.

---

# 37. Save/load

Implement basic persistence using Godot-safe project-owned serialization (`FileAccess`, JSON/binary data, custom Resource serialization, or another robust local format).

Save at least:
- player position;
- health/armor;
- money;
- owned/purchased weapons;
- ammo;
- current time;
- basic settings;
- optional last vehicle/garage state.

The game should recover gracefully if some dynamic world objects are not persisted.

---

# 38. Admin / benchmark menu — mandatory

Create a hidden or explicit benchmark/debug menu for rapid YouTube testing.

It must allow:
- teleport to key districts;
- spawn any implemented vehicle;
- spawn helicopter;
- spawn airplane;
- spawn boat;
- give any implemented weapon;
- refill ammo;
- set money;
- set health/armor;
- set wanted level 0–5;
- clear wanted level;
- spawn police;
- set time;
- set weather;
- repair current vehicle;
- open/test vehicle customization;
- unlock all vehicle modification options;
- give parachute;
- refill lung capacity / toggle scuba for testing;
- max/reset character skills;
- call taxi;
- toggle wildlife;
- toggle invulnerability;
- toggle traffic;
- toggle pedestrians;
- show FPS;
- show coordinates/sector.

This is a testing tool, not a mission system.

It should make it easy to demonstrate the whole project on video.

---

# 39. Blender project organization

Inside `GodotSonnet5.5GTA.blend`, organize major assets into clear collections such as:

```text
GTA_GODOT
  Characters
  NPCs
  Vehicles
    Cars
    Motorcycles
    Boats
    Helicopters
    Airplanes
  Weapons
  Buildings
  StreetProps
  Interiors
  Nature
  VFX_HelperMeshes
  CollisionHelpers
```

Use consistent naming.

Avoid thousands of unnamed objects such as:

```text
Cube.001
Cube.002
Cube.003
```

for final assets.

---

# 40. Godot asset organization

Organize project content clearly, for example:

```text
res://
  gta/
    code/
      core/
      player/
      vehicles/
      traffic/
      ai/
      police/
      weapons/
      combat/
      world/
      streaming/
      ui/
      audio/
      save/
      debug/
      editor/
    generated/
      models/
      materials/
      textures/
      animations/
      audio/
      vfx/
    scenes/
      characters/
      vehicles/
      weapons/
      world/
      props/
      bootstrap/
      sectors/
    resources/
      data/
      themes/
      registries/
```

Use `.tscn`/PackedScene assets for reusable scene composition and `.tres`/custom Resource assets for data where appropriate.

Avoid an unnecessarily huge scene tree. Large amounts of world data, traffic state, inventories, registries and sector metadata should live in compact data structures rather than thousands of permanent Nodes.

Adapt this structure to the actual project as needed.


---

# 41. Blender export pipeline

Create a reproducible Blender → Godot pipeline.

Preferred flow:

```text
GodotSonnet5.5GTA.blend
→ Blender MCP edits
→ save source
→ export GLB/glTF
→ res://gta/generated/models/...
→ Godot import
→ material/resource assignment
→ `.tscn`/PackedScene generation/configuration
→ gameplay integration
```

For Godot, **GLB/glTF 2.0 is the preferred interchange format** for most static and rigged assets because it integrates cleanly with Godot's 3D import pipeline.

Use FBX only when the actual installed Godot version and the specific asset validate more reliably with FBX.

For characters/animated assets:
- preserve skeleton;
- preserve animation clips when appropriate;
- validate bone orientation and scale;
- configure Godot animation retargeting when useful.

Do not rely on manually exporting every asset through Blender's GUI.

Use Blender MCP and Blender Python invoked through MCP when appropriate to automate:
- export paths;
- selected collections;
- transforms;
- triangulation only where necessary;
- material slots;
- animation export;
- LOD variants.

Do not depend on direct runtime use of the master `.blend` file. `GodotSonnet5.5GTA.blend` is the editable source; explicit GLB/FBX exports are the runtime/import artifacts.


---

# 42. Materials and textures

Choose the material and texture treatment yourself as part of the art direction.

No material or texture style is prescribed. Choose the treatment yourself and keep it coherent with the rest of the game.

Create project-owned materials/textures that are coherent with the style you choose.

Useful material categories may include:
- road/asphalt-like surfaces;
- concrete/stone-like surfaces;
- building façades;
- glass;
- metal;
- vehicle body materials;
- tires;
- clothing;
- skin/hair or stylized equivalents;
- wood;
- vegetation;
- dirt/sand/rock;
- water;
- emissive signs/lights.

Use Blender materials, generated textures and the engine's native material/shader system as appropriate.

Keep the pipeline efficient and reusable. Use atlases, trim sheets, material instances/variants or shared shader resources when they materially help.

Do not copy copyrighted GTA/RDR texture assets.
---

# 43. LODs

Create an appropriate LOD strategy for:
- vehicles;
- buildings;
- trees;
- street props;
- NPCs.

Use Godot visibility ranges/manual mesh LODs and generated lower-detail variants where appropriate.

Use `MultiMeshInstance3D` for large quantities of repeated vegetation/props when it materially reduces node count and draw overhead.

Do not render every high-detail mesh at full resolution across the entire city.


---

# 44. Lighting

Choose the lighting style yourself as part of the overall art direction.

The lighting system should:
- make gameplay readable;
- support day/night;
- support street/building/vehicle lights;
- support police/emergency lights;
- support interiors where implemented;
- support weather changes;
- remain performant during recording.

Use the current engine's lighting, fog, shadow, reflection and post-processing features as appropriate for the style you choose.

Do not impose a visual target beyond the art direction you choose.
---

# 45. VFX

Create useful effects for:
- muzzle flashes;
- bullet impacts;
- sparks;
- dust;
- explosions;
- fire;
- smoke;
- vehicle damage;
- rain;
- water splashes;
- tire smoke;
- skid effects;
- helicopter dust;
- police lights.

Use Godot-native VFX systems such as:
- `GPUParticles3D`;
- `CPUParticles3D` where more appropriate;
- ShaderMaterial effects;
- Decal nodes;
- lights and emissive materials.

Keep common effects pooled/reusable and performance-conscious.


---

# 46. Interaction quality

Add feedback so systems feel intentional:
- enter vehicle animation/transition;
- weapon equip;
- reload;
- recoil;
- hit reactions;
- vehicle impact feedback;
- police sirens;
- screen feedback for low health;
- subtle camera effects;
- pickup feedback;
- UI sounds.

Keep UI feedback consistent with the art direction and gameplay needs.

---


# 46A. Character skill progression

Add a lightweight use-based character-stat system inspired by GTA V's single-player attributes.

High-value skills:

- **Stamina** — improves sustained sprinting/cycling/swimming.
- **Shooting** — modestly improves recoil control/reload handling.
- **Strength** — improves melee performance and physical resilience.
- **Stealth** — improves quiet movement/detection profile.
- **Driving** — improves difficult vehicle control/recovery slightly.
- **Flying** — reduces turbulence/handling penalties and improves aircraft control slightly.
- **Lung Capacity** — increases underwater breath time.

Skills should improve primarily by doing the relevant activity.

Keep benefits noticeable but not so strong that low-skill gameplay feels broken.

Expose current stats in a pause/status screen or debug menu.

The system is free-roam progression and must not create mission prerequisites.

---

# 47. World activities — but NO missions

Do not implement missions.

Allowed free-roam activities/interactions include:
- driving;
- flying;
- boating;
- shooting;
- police chases;
- shops;
- garage/vehicle spawning;
- swimming;
- exploration;
- stunts;
- emergent traffic accidents;
- fighting;
- changing time/weather through debug tools;
- sandbox destruction.

Do **not** add:
- mission start markers;
- quest objectives;
- NPC quest givers;
- story cutscenes;
- campaign progression;
- scripted heists;
- mission rewards.

---


# 47A. Optional hobbies and free-roam activities

GTA V contains many activities that are not part of the core story. Add a **small selection only after the primary sandbox is stable**.

These are optional stretch goals and must not become quests/missions.

Good candidates:

- shooting range;
- street race;
- off-road race;
- sea race;
- time trial;
- parachute/base-jump challenge;
- triathlon;
- golf putting/driving-range style activity;
- tennis;
- darts;
- stunt jumps.

Implementation rule:

- activities begin only when the player deliberately interacts with an activity point;
- no story dialogue/campaign progression;
- simple score/time/reward is acceptable;
- do not spend core-development time implementing all of them before police, traffic, vehicles and combat are stable.

## Shooting range

Highest priority among activities because it reuses the combat system.

Support:
- timed target sequences;
- score;
- accuracy;
- optional small cash reward;
- contributes to Shooting skill.

## Stunt jumps

Place optional stunt locations around the map.

Track:
- successful jump;
- distance/airtime;
- safe landing.

This adds exploration value without requiring missions.

---

# 48. Difficulty and player survivability

Implement:
- health;
- armor;
- damage;
- fall damage;
- vehicle collision damage;
- bullets;
- explosions;
- drowning if appropriate;
- death/respawn.

On death:
- fade/death UI;
- respawn at a sensible location/hospital-like respawn point;
- reset wanted level;
- preserve basic sandbox access.

---

# 49. Performance targets

The project must remain playable.

Avoid:
- one Node/script with `_process()` or `_physics_process()` per tiny prop where unnecessary;
- thousands of unpooled traffic/NPC objects;
- expensive AI for distant entities;
- rendering all interiors;
- heavy per-frame reflection updates everywhere;
- all vehicles/NPCs simulating across the full map;
- unbounded rigidbodies.

Use:
- pooling;
- distance-based simulation tiers;
- LOD;
- streaming;
- simplified distant AI;
- culled interiors;
- sensible traffic/pedestrian caps.

Prefer stable 30–60 FPS at reasonable recording settings over theoretical ultra graphics that are unusable.

---

# 50. AI simulation tiers

Use simulation levels:

### Near player
Full:
- animation;
- physics;
- driving;
- combat;
- reactions.

### Medium distance
Reduced:
- simplified AI;
- limited updates.

### Far distance
Represented minimally or despawned.

This is especially important for:
- pedestrians;
- civilian traffic;
- police units.

---

# 51. Priority order

This project is extremely broad.

Use this implementation priority:

1. stable Godot project;
2. player + camera;
3. compact 600×600 m world foundation;
4. one polished Blender-authored car + enter/drive/exit;
5. traffic foundation;
6. player weapon/combat foundation;
7. NPC/pedestrian foundation;
8. police + wanted system;
9. broaden vehicle roster;
10. complete, dense and varied compact map;
11. helicopters/airplanes/boats;
12. broaden weapon roster;
13. vehicle customization/repair;
14. shops/economy/player customization;
15. cover/stealth/drive-by polish;
16. day/night/weather;
17. better NPC reactions and witness behavior;
18. parachute/diving/wildlife/public transport;
19. vehicle damage/explosions;
20. art-direction/material/lighting polish pass;
21. character-stat progression;
22. selected free-roam activities;
23. additional world interaction;
24. benchmark/debug menu;
25. final QA and optimization.

Do **not** stop at step 4.

Continue adding working breadth for as long as the session allows.

---

# 52. Definition of a strong first milestone

A strong first milestone requires:

- player can walk in third person;
- the compact 600×600 m map is playable and meaningfully populated;
- at least one finished Blender-authored car exists;
- player can enter/drive/exit it;
- basic traffic exists;
- at least one finished Blender-authored firearm exists;
- player can shoot;
- pedestrians exist;
- police can respond;
- wanted stars work;
- basic UI works.

Once this is stable, continue expanding toward the full scope.

---

# 53. Do not fake breadth

Do not populate menus with 30 vehicles if only one actually works.

A feature may be marked:

```text
WORKING
PARTIAL
NOT IMPLEMENTED
```

Only mark `WORKING` if it has a functional in-game path.

For decorative-only assets, label them clearly.

---

# 54. QA workflow

Continuously:
- parse/validate GDScript;
- launch/load the project;
- inspect Godot output/errors;
- fix script/resource errors;
- test gameplay;
- inspect logs;
- verify imported Blender assets;
- verify scale/orientation;
- verify collision shapes;
- verify material assignment;
- verify Skeleton3D/animations;
- check missing resource paths and NodePaths.

Find the installed Godot executable automatically if possible.

Use command-line/headless validation when useful, adapting commands to the actual executable/version. Example pattern:

```text
godot --headless --editor --path . --quit
```

Use headless/editor scripting to catch:
- parser errors;
- invalid preload/load paths;
- missing resources;
- broken `.tscn` references;
- shader compilation errors;
- startup exceptions.

Run the main scene normally or through automated startup validation where practical.

Do not wait until the very end to discover that the project does not load.


---

# 55. Blender QA

Before accepting major assets:
- inspect silhouette;
- inspect proportions;
- inspect normals;
- inspect materials;
- check scale;
- check origin;
- check transforms;
- remove accidental duplicate geometry;
- check wheel pivots;
- check weapon grip/origin;
- check character rig orientation;
- check object names.

Then validate the exported result inside Godot.

---

# 56. Final Godot validation

Before declaring completion:

1. `project.godot` is healthy;
2. the project opens without critical GDScript/resource/shader errors;
3. the configured main scene loads;
4. player can move;
5. the intended compact map areas are accessible;
6. traffic works;
7. pedestrians work;
8. vehicles work;
9. weapon combat works;
10. police response works;
11. 0–5 wanted system works;
12. player can lose wanted level through real search/LOS behavior;
13. cover and stealth work if marked WORKING;
14. drive-by shooting works if marked WORKING;
15. vehicle modification/repair works if marked WORKING;
16. parachute/diving/taxi/wildlife systems behave correctly if marked WORKING;
17. helicopter or airplane works if marked WORKING;
18. shops work if marked WORKING;
19. admin menu works;
20. Blender-generated assets import/display correctly;
21. no major missing resources/materials;
22. save/load works at least at basic level;
23. world-sector streaming does not produce obvious duplicate/leaked scenes;
24. performance is acceptable for recording.


---

# 57. Required documentation

Maintain:

## `DEVELOPMENT.md`
Include:
- Godot version and renderer;
- render pipeline;
- project architecture;
- controls;
- systems;
- scene layout;
- Blender asset workflow;
- build/run instructions;
- known limitations.

## `FEATURE_MATRIX.md`

Create a table:

```text
Feature | Status | Notes
```

Include all major systems from this prompt.

Use only:
- `WORKING`
- `PARTIAL`
- `NOT IMPLEMENTED`

Be honest.

## `SONNET_5.5_FINAL_REPORT.md`

At completion include:
- what was built;
- what works;
- what is partial;
- known bugs;
- controls;
- build result;
- major assets created in Blender;
- vehicle roster;
- weapon roster;
- map regions;
- wanted/police implementation;
- performance notes.

---

# 58. Session timing, token accounting and API-equivalent cost — mandatory

These metrics will be shown in a YouTube video that tests Claude Sonnet 5.5 on several game projects. Measure **only this Claude Sonnet 5.5 Godot GTA project**. Do not include other sessions, other projects or earlier benchmarks, and **do not fabricate precision**.

## 58.1 Development time

At the very beginning, before substantial work:

1. Read the current operating-system timestamp with its timezone.
2. Create a unique run directory and save the start time:
   ```text
   .sonnet-5.5-gta-runs/<run-id>/start_time.txt
   ```
3. Preserve that run ID and original start time throughout the task.

After final implementation, testing and report preparation:

1. Read the operating-system timestamp again.
2. Save it to the same run directory:
   ```text
   .sonnet-5.5-gta-runs/<run-id>/end_time.txt
   ```
3. Calculate the elapsed wall-clock duration from the recorded timestamps.

Include planning, coding, Blender MCP work, model creation, exports/imports, Godot import, GDScript parsing, scene loading and runtime validation, debugging and command/build waits. Report start, end, `HH:MM:SS`, elapsed minutes and, if useful, decimal hours.

If work resumes, append identifiable segments instead of overwriting the original start or earlier results. Report known pauses separately. Do not sum overlapping tool/subagent durations into wall-clock time. Do not claim measured active-work time unless it was tracked separately.

## 58.2 Token usage from the actual Claude session

Obtain real usage from the runtime in which this agent is actually running. Preferred sources are:

1. request/session usage metadata exposed directly by the current Claude agent or its host;
2. a usage/status record for this exact session, if available;
3. the current session's permitted local usage log, only if it can be identified reliably;
4. another official usage source that isolates this task.

Do not assume that a host exposes the same tools or log layout as standalone Claude Code. Identify the session using its ID, working directory and timestamps. Read only relevant usage metadata; do not copy credentials, raw private conversations or unrelated session data into the repository/report.

For a previously used session, record its baseline cumulative counters or filter the requests belonging to this task. Identify task-owned delegated work separately and avoid counting it both in a parent total and again in a child total. Record the actual model used by each identifiable delegated part rather than attributing everything to the requested model automatically.

Where available, report input, cache-read, cache-write, output, separately exposed thinking/reasoning tokens, and a deduplicated total. Distinguish cache-write durations if they are separately reported.

### Normalize token categories before counting

For raw Anthropic Messages usage, verify the meanings of `input_tokens`, `cache_read_input_tokens` and `cache_creation_input_tokens` against the official caching documentation [API-C]. Treat a host's aggregated input counter according to its own documented semantics, not as automatically identical to the raw API fields.

Use mutually exclusive categories. Do not subtract cache usage from an already uncached input count. Do not add cache-write duration subtotals on top of their parent total. Do not add thinking/reasoning tokens again when they are included in output.

Determine whether events are per request, streaming updates, nested iteration totals or cumulative snapshots before summing them. Deduplicate using available request/message identities. A missing counter is **unknown**, not zero. Do not estimate token consumption from source-code length, asset size, tool-call count or elapsed time.

Record the observation cutoff and any final response/reporting work not included in the available counters. If exact token usage cannot be obtained, write:

```text
Exact token usage unavailable from the accessible runtime.
```

Only provide a labeled estimate if its data and method are defensible.

## 58.3 Claude Sonnet 5.5 API-equivalent price

Calculate the **token-only API-equivalent cost in USD** from verified usage. This is a benchmark equivalent, **not the user's Claude subscription payment, host-application credits or actual account bill**.

First verify the model identifier exposed by the session. Use official Anthropic pricing for that actual model [API-P], not rates inherited from another model or provider. Record the source URL, verification date and comparison tier. No fixed price table is assumed in this prompt.

Use Standard Claude API pricing as the stated comparison basis unless the user requests another basis. Distinguish that benchmark choice from an actual Fast, Batch, partner-hosted or other service tier; do not silently mix tiers. Apply only verified cache, context, duration or other pricing rules appropriate to the chosen basis. Do not change model settings just to simplify the report.

Normalize counts and compute:

```text
request_api_equivalent_usd =
    sum(exclusive_category_tokens * verified_category_rate_per_million) / 1_000_000

project_api_equivalent_usd =
    sum(request_api_equivalent_usd for requests belonging to this project)
```

If different task-owned requests actually used different models, calculate their subtotals at the corresponding verified rates and disclose them. Do not label a mixed-model subtotal as pure Sonnet 5.5 consumption.

If the official price, required category split or model identity is unverified, state the limitation. A supported range or partial estimate must be labeled and its assumptions shown. Otherwise report:

```text
Claude Sonnet 5.5 API-equivalent cost unavailable because usage or authoritative pricing could not be verified.
```

### Tool fees

Keep separately metered external tool charges outside the token-only total and report them only when known. Do not invent a separate API fee for local Blender or the game engine. Model tokens used for tool instructions and results remain part of the measured model usage; do not add a second token charge for them.

### Official sources for accounting, not new gameplay requirements

[API-P] Anthropic model and feature pricing; verify at execution time: `https://platform.claude.com/docs/en/about-claude/pricing`

[API-C] Anthropic prompt-caching usage fields; verify the actual runtime's mapping: `https://platform.claude.com/docs/en/build-with-claude/prompt-caching`

## 58.4 Required metrics in `SONNET_5.5_FINAL_REPORT.md`

At the bottom of `SONNET_5.5_FINAL_REPORT.md`, include:

```text
## Claude Sonnet 5.5 GTA Session Metrics

Project: Godot GTA sandbox
Run/session identifier:
Working-directory full path:
Start timestamp and timezone:
End timestamp and timezone:
Elapsed wall-clock time (HH:MM:SS):
Elapsed minutes:
Elapsed hours:
Known pauses / resumed segments:

Requested model: Claude Sonnet 5.5
Actual model identifier(s):
Thinking/effort setting (if exposed):
Input tokens (state whether uncached or inclusive):
Cache-read tokens:
Cache-write tokens:
Cache-write duration breakdown (if exposed):
Output tokens:
Thinking/reasoning tokens (included / separate / unavailable):
Deduplicated total tokens:
Usage source and observation cutoff:
Unmeasured work / limitations:

Token-only API-equivalent cost (USD):
Per-model subtotals (if applicable):
Official pricing source, verification date and comparison tier:
Rates and formula used:
Cache/context/tier adjustments or explicit assumptions:
External tool/API fees (known / excluded / unknown):
Measured / estimated / unavailable, with reasons:

Blender MCP server/tool namespace actually used:
Blender host: localhost
Blender port: 9890
Blender master file: GodotSonnet5.5GTA.blend
Verified full path of master file:
Approximate number of major Blender assets created:
```

In the final message, explicitly provide **total development time, total tokens, and API-equivalent USD cost for this project**, with each figure marked measured, estimated or unavailable. These metrics are mandatory reporting fields, not permission to invent unavailable numbers. Finish the validation pass before recording the final observations.

---

# 59. Git / recovery

Use Git where practical.

Create meaningful milestone commits, for example:
- baseline;
- player;
- first drivable car;
- combat;
- police/wanted;
- world expansion;
- air vehicles;
- final stabilization.

Do not commit:
- `.godot/`;
- generated import/cache data;
- logs;
- export/build outputs;
- large generated caches;
- other standard Godot transient data.

Do not allow an experimental change to destroy the only working state.

---

# 60. Final asset-quality gate

Before final completion, visually inspect the game and reject **unintentional placeholder content**.

Important visible content should not remain as raw engine primitives or temporary debug assets unless that is a deliberate, coherent part of the art direction you chose.

Prioritize authored/finalized versions of:
1. player character;
2. main vehicles;
3. police;
4. common pedestrians;
5. weapons;
6. important buildings/landmarks;
7. street props.

Any intentionally chosen visual style is acceptable if it is applied consistently.

The problem is unfinished placeholder presentation, not any specific art style.

Document any remaining placeholder or incomplete assets honestly.
---

# 61. Final response

Do not finish by only saying "done".

Before responding:

1. run final validation;
2. fix critical parse/runtime errors;
3. inspect `FEATURE_MATRIX.md`;
4. update `SONNET_5.5_FINAL_REPORT.md`;
5. save `GodotSonnet5.5GTA.blend`;
6. ensure exported Blender assets exist in the Godot project and import cleanly;
7. confirm the game launches into free roam;
8. confirm there are **no missions**;
9. confirm the admin/benchmark menu provides rapid access to implemented systems;
10. make a final Git commit if the repository is healthy.

Then provide a concise final summary with:

- how to launch;
- controls;
- map regions;
- vehicle list;
- weapon list;
- wanted/police features;
- Blender assets created;
- what remains incomplete;
- elapsed development time;
- token usage if available;
- Claude Sonnet 5.5 token-only API-equivalent cost in USD if calculable;
- whether the reported metrics are exact or estimated.

---

# 62. Start now

Begin immediately.

First:
- record the start timestamp and run ID as described in Section 58;
- inspect the existing Godot project;
- verify and bind the project-specific Blender MCP connection as required by Section 0;
- verify `GodotSonnet5.5GTA.blend`;
- assess render pipeline;
- create the implementation plan.

Then build the game autonomously.

Remember:

**This is a missionless GTA-style free-roam sandbox on a compact approximately 600×600 meter map. The visual style is your decision.**

**Godot is the game engine.**

**Use only the verified Blender MCP connection on `localhost:9890` with `GodotSonnet5.5GTA.blend` in the current project folder for the mandatory Blender asset pipeline.**

**Use Blender actively, not merely as an optional export tool.**

---

# 63. FINAL REQUEST — time, tokens and API-equivalent cost (do this last)

When the game, the documentation and all validation are finished, **calculate and report the following three numbers for this project**, following Section 58 exactly:

1. **Time spent on the project** — wall-clock duration from the start timestamp you saved at the very beginning (`.sonnet-5.5-gta-runs/<run-id>/start_time.txt`) to a fresh end timestamp (`end_time.txt`), as `HH:MM:SS`, plus total minutes. Report known pauses separately.
2. **Number of tokens** — real usage of this session from the runtime (input, cache-read, cache-write, output, thinking if separately exposed, and a deduplicated total). If exact usage is unavailable, write exactly: `Exact token usage unavailable from the accessible runtime.` Never estimate from code size, tool-call count or elapsed time.
3. **Price in API-equivalent US dollars** — the token-only cost computed from the verified usage at the official Anthropic API price of the model you actually ran as (Claude Sonnet 5.5, standard API pricing; verify at `https://platform.claude.com/docs/en/about-claude/pricing`). This is a benchmark equivalent, not the user's subscription bill. If usage or pricing cannot be verified, say so instead of guessing.

Write these numbers into the `Claude Sonnet 5.5 GTA Session Metrics` block at the bottom of `SONNET_5.5_FINAL_REPORT.md` **and** state them in your final chat message, each marked as measured, estimated or unavailable.
