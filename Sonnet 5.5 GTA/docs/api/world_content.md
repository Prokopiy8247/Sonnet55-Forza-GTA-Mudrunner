# World content (World-Content agent) - buildings, landmarks, street furniture, vegetation

Owner files: `gta/code/world/{city_builder,building_kit,landmark_builder,street_furniture,nature_builder,facade_materials}.gd` plus helpers
`content_{batch,lib,mesh,modules,props,prop,manager}.gd`, shaders `gta/generated/shaders/building_*.gdshader(inc)`, tests `gta/tests/content_*.gd`.

## 1. Entry point and data flow

```gdscript
CityBuilder.build(world: Node3D)   # called ONCE by WorldRoot.setup() after WorldLayout is generated (idempotent: build() clears the previous result)
CityBuilder.clear()                # frees everything the last build created (tests / re-layout)
CityBuilder.last_stats             # Dictionary: ms, marks{library,buildings,furniture,nature,flush}, instances, multimeshes, colliders, buildings, modules,
                                   #   kit_parts, fallbacks, fallback_keys, furniture{}, nature{}, landmarks{}
```

Reads `WorldLayout.lots / furniture / nature_zones / roads / piers / locations / signals` + `terrain_height()/is_water()/signal_state()`.
All static content is created through `world.get_sector_parent(pos)` (100 m cells, falls back to an internal `CityContent/Sector_n` when the world has none), so
`SectorManager` hides it with the sector. Dynamic bodies go under `world.get_dynamic_parent(pos)`.

Boot cost on the real map (110 buildings, 880 furniture items, ~370 trees): **~1.0 s** (budget 4 s). Memory: ~10 000 MultiMesh instances in ~780 MultiMeshInstance3D.

## 2. What it builds

| content | how | nodes / groups |
|---|---|---|
| Buildings (`office apartment shop house warehouse factory hangar parking`) | 4 m bay modules from `buildings/kit_*.glb` (parts registered as `K:<PartName>`; ground floors 4.8 m, upper 3.6 m, last bay of every face = `*_Corner_Out`, cornice, `Office_Crown_A` stack on tall towers, awnings / signs / pilasters / balconies / fire escapes, roof props `K:Roof_*`, sawtooth roofs on warehouses, set-back crowns). Houses = `bld_house_a..d`, `bld_duplex`; big apartment lots may use `bld_apartment_small`; big warehouse lots may use `warehouse_a/b` | `MM_<key>` MultiMeshInstance3D per (sector, module); StaticBody3D `Col_concrete` (group `world_static`, meta `surface`) |
| Far LOD | `far_box` MultiMesh (unit box + `building_far.gdshader`: procedural window grid, cornice band, ground band, lit panes) visible from 225 m; `shadow_box` = shadows-only box so detailed modules cast no shadows | `MM_far_box`, `MM_shadow_box` |
| Helipad | on the lot containing `helipad_downtown` (`K:Roof_Helipad_Pad`, scaled to the roof) | `MM_K_Roof_Helipad_Pad` |
| Landmarks (`lot.kind == landmark`) | `buildings/<lot.landmark>.glb` (aliases: airport_terminal->terminal, airport_tower->control_tower, marina_office->pier_hut), centred on the lot, front edge 1.5 m behind the lot front; collider = box of the AABB (or trimesh of a `Collision*` mesh). Missing GLB -> BuildingKit stand-in or code-built gas station / tower (logged) | `Landmark_<id>` Node3D holding `Marker3D` of every GLB empty (group `landmark_anchor`, meta `landmark`); `Anchor_<location_id>` Marker3D (group **`location_anchor`**, meta `location_id`, `landmark`, `radius`) at the matching `WorldLayout.locations` (id match or inside the lot) |
| Street furniture | `props/*.glb` found by token (`street_lamp`, `traffic_light`, `stop_sign`, `speed_sign`, `fire_hydrant`, `bench`, `trash_bin`, `bollard`, `bus_stop`, `road_cone`, `road_barrier`, `fence*`, `utility_box`, `mailbox`, `parking_meter`, `billboard`), else code-built fallback | static ones: MultiMesh per sector + collider; lamps: `Node3D` in group **`street_lamp`** (meta `lamp_height`, `lamp_offset`); dynamic: `ContentProp` (RigidBody3D, layer `GC.L_PROP`, groups `damageable`, `smashable_prop`) |
| Traffic signals | MultiMesh instance per signal head set; lens materials `SignalRed/Amber/Green` read the state from the instance custom data x (0 green, 1 yellow, 2 red) | `ContentManager` updates the state every 0.25 s from `WorldLayout.signal_state(signal_id, phase, t)` |
| Vegetation | zones from `WorldLayout.nature_zones` (forest / park / hills / beach_palms / roadside) + furniture `palm` / `tree_street`: oak, pine, birch, palm, bushes, rocks, grass tufts, reeds along the shore, flower patches, logs, stumps, driftwood, shells. Near mesh + `_lod` mesh (visibility ranges 150 m / 120..420 m), wind sway in the shader, trunk colliders only within 12 m of a road | `MM_nat_*`, `Col_wood` |

### Roles of the contract
* Facade modules are open shells: a solid `core` box per tier is added behind them, a box collider per tier, roof deck + roof props.
* Windows: shader `building_window.gdshader` replaces the Blender `Window` material. UV in metres; per-pane lit state from a hash of (pane cell, building random, instance random),
  progressive switch-on with the global `gta_night`, "bedtime" turn-off after 22:30 (clock pushed by `ContentManager` from `Game.time_of_day`), warm / orange / white / cyan(TV flicker) / magenta panes.
* Walls: `building_wall.gdshader` (palette 0..3 per lot x slots WallA..D / Roof / Trim, vertex-slot merged surface, grit, ground grime, wet gloss from `gta_wetness`).
  All opaque wall-shader surfaces of a module are merged into ONE surface (vertex alpha = slot / 8) -> ~2 surfaces per module.
* Neon / lamps: `building_neon.gdshader` (night driven, per-instance hue, billboard art pattern for `BillboardFace`/`NeonBillboard`/`NeonAd`).
* Foliage: `building_foliage.gdshader` (vertex-alpha sway weight, rain / storm bends harder through `gta_rain`).

## 3. Public API of the helpers

```gdscript
FacadeMaterials.wall(slot) / wall_merged() / window(variant) / neon(color, day, night, hue_from_instance) / signal_lens(1..3) / foliage(kind) / billboard() / generic(color)
FacadeMaterials.for_glb(material_name, src_material) -> Material   # the replace-by-NAME table (WallA..D, Roof, Window, Signal*, LampGlow, Neon*, Glass, ...)
FacadeMaterials.set_hour(h)                                         # window "lights out" clock (ContentManager does it)
ContentLib.flatten(root, skip, foliage_kind) / kit_parts(rel) / register_glb_optional(key, rel) / meshes / aabbs / sources / fallbacks
BuildingKit.specs / towers / build_block|build_house|build_industrial|build_hangar|build_parking(batch, lot, rng, ...)
StreetFurniture.find_glb(kind) / stats ;  NatureBuilder.stats / placed_trees / variant_count ;  LandmarkBuilder.stats / GLB_ALIAS
ContentManager.set_signal_clock(callable)   # Traffic may call this with its own clock so lights match its stop logic (default: Time.get_ticks_msec()/1000)
ContentManager.register_prop(body)          # extra smashable bodies can be handed to the distance manager
```

`ContentProp.apply_damage(amount, info)` wakes the body and launches it at `1.8 + 0.1*amount + 0.01*impulse` m/s (clamped 2.2..16) along `info.direction` (+ upward bias).

## 4. Furniture / lot data conventions used (World-Layout contract)
* `furniture[i].yaw` = facing direction (front = -Z rotated by yaw, `Util.dir_to_yaw`). Lamp arms point to -Z; traffic-light GLB has its mast arm toward +X and heads facing -Z.
* Signals: `signal_id` indexes `WorldLayout.signals`; `phase` (0/1) is read from the item (missing -> derived from the facing axis: Z-facing = 0, X-facing = 1).
* Lots: `rect` (x,z min corner), `yaw` (front faces the street), `floors` (>=1), `palette` 0..3, `landmark` id. Building height = `4.8 + 3.6*(floors-1)` with the kit ground modules.
* Street trees (`palm`, `tree_street`) on the roadway are skipped.

## 5. Tunables (constants)
`BuildingKit.NEAR_END 270 / FAR_BEGIN 225 / DETAIL_END 115`, `NatureBuilder.NEAR_END 150 / FAR_BEGIN 120 / FAR_END 420 / MAX_TREES 3200 / MAX_TUFTS 9000 / MAX_TRUNK_COLLIDERS 420`,
`StreetFurniture.MAX_DYNAMIC 150`, `ContentManager.TICK 0.25` (props frozen > 150 m, released < 120 m), `ContentBatch.CELL 100`.

## 6. Performance (real map, 1280x720 windowed, RTX 5070)
Street level downtown, traffic + pedestrians enabled: **1170 draw calls**, CPU render 1.2 ms, GPU 1.3 ms, ~1.4 M primitives (incl. shadow passes), 181 fps.
Night street view: 946 draw calls. Measured with `tools\gd.ps1 game -GameArgs "--exec=res://gta/tests/content_perf.gd --cam=..."` (prints `PERFRT`).
Tricks: modules as MultiMesh per (sector, kit part); wall surfaces merged per module; shadow passes use one `shadow_box` MultiMesh per sector; detail props (AC, tanks, awnings,
signs, fire escapes) fade at 115 m; far boxes after 225 m; trees LOD pair; grass 55 m.

## 7. Fallbacks and missing assets (logged with `push_warning`, listed in `CityBuilder.last_stats["fallback_keys"]`)
Nothing is currently on a code-built fallback except where the Blender asset does not exist: landmarks `dealer_lot`, `shooting_range` (and any `train_station_*` without a GLB) use a BuildingKit stand-in;
`airport_tower`/`gas_station` code-built meshes exist only for missing GLBs. Code-only helpers (`far_box`, `shadow_box`, `core`, `post`, `deck`, `roof_slab`, `gable`, `arch`, `chimney`, `hangar_door`, `park_bay`) are not Blender assets by design.

## 8. Tests
`gta/tests/content_buildings_test.gd`, `content_furniture_test.gd`, `content_nature_test.gd`, `content_landmark_test.gd` (headless `exec`), `content_perf.gd` (render cost, `game`),
`content_showcase.gd` / `content_closeup.gd` / `content_kit_view.gd` (screenshots via `shot`), `content_mock.gd` (mock layout used only when `WorldLayout.lots` is empty), `content_layout_probe.gd`.

## 9. Known limits
* Recommended project setting (not mine): `rendering/occlusion_culling/use_occlusion_culling=true` - buildings are not registered as occluders yet.
* No interiors; facade modules are visual shells + box colliders (no per-window collision, no breakable glass).
* `MultiMesh.get_instance_*` readbacks return zeros under `--headless` (dummy renderer): tests use manager / builder state instead.
* Landmark colliders are one box (or a `Collision*` trimesh when the GLB has one), so porches / awnings are not collidable.
* Windows are lit per pane, not per room; there are no interior lights.
