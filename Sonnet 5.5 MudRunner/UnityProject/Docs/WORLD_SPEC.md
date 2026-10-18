# WORLD_SPEC — procedural wilderness + proving ground (contract for the world worker)

The world is **generated at run time from code + a seed** (deterministic). Nothing big is stored in assets/git. It produces a `WorldData`
(`Assets/Game/Runtime/Game/GameManager.cs`): a `GroundMap` (heights, 8 surface-layer weights, hidden extra depth, base wetness), a `WaterMap`,
prop placements, teleport points, route polylines and objective sites. `GameManager.StartWorld(kind)` calls `WorldBuilders.Registry[kind]`;
register your builders for `WorldKind.Wilderness` and `WorldKind.ProvingGround` (currently a tiny `DemoArena` is the fallback).

## 1. Coordinates and data
* One shared map: 2049 × 2049 samples, 1.0 m spacing → x, z ∈ [−1024, 1024] (origin of sample (0,0) = (−1024, −1024)). X east, Z north, Y up, metres.
  (If generation proves too slow you may use 0.75 m spacing, but keep world size 2048 m.)
* Wilderness playable area: x, z ∈ [−768, 768] (≈ 1.5 km square = 2.4 km²). The outer 256 m ring is rising steep forested mountains/cliffs (slope ≥ 35°, heights up to +70 m) acting as natural walls; add invisible kill/reset boxes only as a safety net.
* **Proving ground**: east strip x ∈ [800, 1010], z ∈ [−300, 300], separated from the wilderness by a ridge (x ≈ 770–800) crossed by a signposted gravel track from the base camp (so it is reachable by driving) – also reachable via debug menu teleport points.
* `GroundMap` API: see `Assets/Game/Runtime/Ground/GroundMap.cs` (`SetWeights`, `SetExtraDepth(ix,iz,metres)`, `SetBaseWetness`, `Finalize_()`). Layers: 0 Rock, 1 FirmSoil, 2 Grass/forest floor, 3 Gravel/road, 4 ShallowMud, 5 DeepMud, 6 Bog, 7 Sand. `extraDepth` makes a patch that LOOKS like ordinary mud/grass much deeper (hidden traps, up to +2 m).
  Physics meaning (`SurfaceParams.cs`): firm soil/grass/gravel/rock support vehicles; shallow mud slows; deep mud needs low range + diff locks (light vehicles bog down); bog/swamp traps everything without winch.
* `WaterMap` API: `Assets/Game/Runtime/Ground/WaterMap.cs` (surface Y + current per cell, 1 m cells like the ground). `map.water = new WaterMap(...)`. Rivers need the river BED lowered in the heightmap below the water surface; fords are shallow stretches (0.4–1.0 m deep) of the river with a gravel/sand bed; deep sections (> 1.8 m) are impassable for the scout/utility.
* Generation budget: whole world < 8 s on the dev machine (use Burst/Jobs or tight loops; `Unity.Mathematics` noise is available). Memory < 400 MB.

## 2. Wilderness layout (design intent – refine freely, keep the features and route character)
```
   N
   ^   (-768,768)                                              (768,768)
   |      NW highlands/pine ridge ........ north ridge track ............ NE swamp basin (bog) + cabin island (Cabin)
   |      Watchtower (-450,480)                                              ^ objective C (550,480)
   |            .                                   Logging landing (−150,420)   ~~~ bog / reeds ~~~
   |      west track                      Silverrun River meanders W->E through the middle (z ≈ 0 .. -120)
   |        Base camp + garage + fuel station (−600,−560)            fords F1 (−260,−20) F2 (180,−90); old bridge B1 (−20,40) (fragile)
   |                south hills                      Widowmaker mud hill (350,−350)           Pump station (600,−250)
   +--------------------------------------------------------------------------> E
```
* **Base camp / garage** at (−600, −560): flat firm ground clearing (60 × 60 m), garage building (vehicle selection/refuel/repair point), fuel station with 2 pumps and a tank, a few tents/crates/barrels, signposts, winch anchor posts. Player start (−585, −545) facing NE.
* **Key sites** (objective markers + landmarks with distinct silhouettes so the player can navigate by map and compass): Logging landing (−150, 420) with log piles; Cabin on a firm island in the swamp (550, 480); Watchtower on the highest hill (−450, 480, visible from far); Pump station (600, −250); Old sawmill ruin (−300, −200); Radio mast (100, 600).
* **Three route choices** between base camp and the cabin (objective C), each with a different risk profile:
  1. *North road* (long, ≈ 2.7 km): packed gravel/dirt track west → north along the NW ridge, then east along the north ridge, ending with a fragile wooden causeway/bridge through the swamp edge. Mostly firm with muddy stretches (shallow mud puddles, a few ruts), safe for the scout.
  2. *Central track* (medium, ≈ 1.9 km): forest dirt track with deep ruts, shallow/deep mud sections, the Silverrun ford F1 (0.7–0.9 m deep, current ≈ 1.0 m/s) and a steep but short climb; needs care, low range, diff lock for light vehicles.
  3. *Swamp shortcut* (short, ≈ 1.5 km): straight through the south hills, the steep Widowmaker mud climb (18–26° wet mud), the river deep crossing (needs the hauler or a bridge detour) and finally 200 m of bog/deep mud with hidden extra depth around the cabin island; winch anchor trees/posts along it. Fast if it works; a long winch recovery if not.
* **River Silverrun**: meandering, 12–25 m wide, bed 1.5–3 m below the banks except at the fords (gravel bed, 0.4–1.0 m deep), flow 0.8–1.6 m/s toward +x, with oxbow ponds. A second smaller creek in the south with a broken bridge (planks missing) next to a ford.
* **Terrain readability** (gameplay!): firm = dry grass/gravel/exposed rock on ridges and roads; wet ground = darker grass with higher `baseWet`; shallow mud = brown puddly track centres and low spots; deep mud = dark glossy, in ruts/basins and around water crossings; bog = blackish-green with reed clumps, standing water patches, dead trees. Use `extraDepth` for hidden traps on otherwise innocent-looking mud/grass (and tell the player through subtle cues: reeds, darker patch, tyre-track-free area). Existing ruts: pre-carve tracks into the `MudField` (see §4) so tracks look used.
* Vegetation: dense spruce forest on slopes and between tracks (instanced, density from noise + slope + wetness; none in water/bog/track), birches and dead trees in wet areas, reeds in bog/pond shores, stumps and fallen logs along tracks (some logs are dynamic rigid bodies), boulders and rock outcrops on slopes, moss patches. All props are instanced or batched (no one-GameObject-per-tree); trees and structures need colliders only near the player (spawn collider pool within ~80 m).
* **Winch anchors**: place `WinchAnchor` components (see `Assets/Game/Runtime/Vehicles/Winch.cs`) on stout trees/stumps/posts along tracks and at hazards (every 40–80 m on the central and swamp routes, many around the cabin, in the proving ground).

## 3. Proving ground (east strip; compact test arena for demos and automated tests) 
Everything marked by signs/distance poles. From the entrance (north end z=+280... or the south end; choose) lay out in a loop of ~600 m:
* Start/measure zone: flat firm pad 40 × 40 m, painted grid and a 100 m straight with distance poles every 10 m (speed/acceleration measuring), garage + refuel.
* **Mud-pit lane**: 6 pits in a row, each 18 m long and 12 m wide, separated by 8 m firm causeways, with increasing difficulty: (1) shallow mud, (2) shallow + 0.3 m extra depth, (3) deep mud, (4) deep mud + 0.5 extra, (5) bog, (6) bog + 0.8 extra. Depth gauge poles with painted bands at the pit edges.
* **Steep mud hill**: 70 m climb with three steps 12°, 20°, 28° (wet mud surface), run-out plateau, firm return slope; winch anchor trees at the top.
* **Side-slope track**: 40 m cambered track with 14–18° sideways tilt and a mud surface (rollover/drift test).
* **Axle articulation course**: 45 m of boulders (rock props with colliders) alternating left/right with 0.4 m deep holes (heightmap dents) so one wheel droops while the other climbs.
* **River ford**: 36 m long crossing, water surface constant, bed profile 0.4 → 0.8 → 1.2 → 1.6 m deep → back, current 1.5 m/s, with depth markers; a bypass bridge.
* **Log pile and sandbox**: 20 logs as dynamic rigid bodies in a pile, 6 stumps and 4 winch-anchor trees, plus a few barrels/crates as dynamic props.
* **Measuring area**: flat firm pad with a grid of marker cones (static) for turning-circle measurement.
Teleport points (named, used by the debug menu): "Proving ground start", "Mud pits", "Mud hill", "Side slope", "Articulation", "Ford", "Log pile".

## 4. Integration requirements
* Register builders: `WorldBuilders.Registry[WorldKind.Wilderness] = WildernessBuilder.Build;` and for `ProvingGround` – in a `[RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.BeforeSceneLoad)]` static method, so no scene wiring is needed. Return `WorldData` with `map` (+`map.water`), `playerStart`, `playerYaw`, `points` (teleports), and `root` (a GameObject parent that holds everything you instantiate; the GameManager destroys it on teardown).
* Extra data the objectives need: put them in a new `WorldSites` class (static or on a component under `root`): named sites with position/radius (BaseCamp, Garage, FuelStation, Cabin, LoggingLanding, Watchtower, PumpStation, Sawmill, RadioMast), the three route polylines (`Vector3[]`) with names and the proving-ground loop, spawn points for cargo/trailers.
* Water: expose `WaterMap` through `map.water`. A water surface MESH + material is the render worker's follow-up; until then add a simple semi-transparent blue mesh generated from the water raster so the world is not dry. Keep this mesh builder isolated (`WaterSurfaceMesh.cs`) so it can be replaced.
* Ground renderer + collider: after `GroundService.Initialize` the game creates `GroundRenderer`/`GroundColliderBuilder` (Assets/Game/Runtime/Rendering/, written by the render worker; check what exists). If they exist call them from your builder so the world is visible; otherwise leave a clear hook.
* Pre-carved ruts: add `MudField.PrecarveTrack(IList<Vector2> polyline, float width, float depth, ...)` (new method in `MudField.cs`, writes straight into the sparse tile store/window with a Gaussian rut profile and side berms, marks tiles stored) and call it for the dirt/mud tracks once the window exists or by pre-filling the store; document the call order.
* Props: use Blender-authored prefabs/meshes when they exist under `Assets/Game/Art/**` (spruce, rocks, logs, cabin, bridge, ...; the art worker produces them over time, FBX imported by Unity). Until then use code-generated stand-ins behind an interface `IPropLibrary` (`Get(string id)` → mesh + materials + collider recipe) with ids like `spruce_a`, `spruce_b`, `spruce_c`, `birch`, `deadtree`, `rock_s`, `rock_m`, `rock_l`, `rock_slab`, `log_long`, `log_short`, `stump`, `reed`, `bush`, `cabin`, `garage`, `fuel_station`, `watchtower`, `bridge_intact`, `bridge_broken`, `sign_arrow`, `sign_warn`, `post_anchor`, `barrel`, `crate`, `tent`, `fence`. Swapping to real art must be a one-file change.
* Rendering of instanced props: batched `Graphics.RenderMeshInstanced` per (mesh, material, cell) with CPU culling by cell and distance, LOD switch by distance (LOD0/LOD1/billboard if present). No GameObject per tree.
* Tests: `Assets/Game/Tests/PlayMode/WorldTests.cs` – generation determinism (same seed → same hash), time < 8 s, routes connect (a path exists on firm/passable cells between base camp and the cabin for route 1), spawn points are on dry land above ground, all `WorldSites` inside bounds, the proving ground features exist. Plus a batch method `MudRunner.EditorTools.WorldPreview.Run` (GFX=1) that renders a top-down colour-coded surface map PNG of the whole wilderness (`Captures/world_surface.png`) and some perspective views, for human review.

## 5. Working rules
* `python -I Tools/qc.py` after each C# edit; real Unity runs only through `Tools/ub.sh` / `Tools/rt.sh` (they serialise access to the single project; others use Unity too). Never start Unity.exe yourself. No `git commit`. Don't edit ProjectSettings/manifest. Don't touch Blender.
* Own folders: `Assets/Game/Runtime/World/**`, `Assets/Editor/World/**`, `Assets/Game/Tests/PlayMode/WorldTests.cs`; minimal additions allowed to `MudField.cs` (PrecarveTrack) and `GameManager.cs` (registry hooks only).
* Report: what was built, generation time, memory, route lengths measured on the generated map, screenshots, known limitations.
