# World (procedural wilderness + proving ground)

Deterministic generation (seed `WorldGenConfig.seed`) of the 2048 m map. Nothing big is stored in assets.

* `WorldGenerator.Generate(cfg)` -> `GeneratedWorld` (pure data: `GroundMap` + `WaterMap`, tracks, `WorldSites`, `PropSet`). ~4 s, ~250 MB managed.
* `WildernessBuilder.Build()` / `ProvingGroundBuilder.Build()` instantiate it (terrain collider, ground renderer hook, water mesh, instanced props, collider pool,
  structures as GameObjects) and return `WorldData`. Both are registered in `WorldBuilders.Registry` by `WorldRegistration` (BeforeSceneLoad).
  `WorldKind.ProvingGround` uses a cropped 641 m map; the same strip also exists inside the wilderness map (reachable by the service road).
* Authored geography lives in `WorldLayout` (river, ponds, pads, traps, sites, tracks) and `PgLayout` (proving ground stations). Terrain functions: `TerrainGenerator`
  (+ `.PG.cs`). Tracks: `WorldTracks.cs` (dense Catmull-Rom, grade-limited vertical profile, ford / bridge / causeway / free segments). Rivers: `WorldRiver.cs`.
* `WorldSites` (static `Current`): named sites, the three route polylines, bridges (with load limits), fords, traps, anchors, cargo / trailer spawns, garage zones.
* Pre-carved ruts: `MudField.PrecarveTrack(polyline, gauge, depth, ...)`. Call order: builder returns -> `GroundService.Initialize` (field exists) -> `WorldRuts.Apply(field, gw)`
  (hooked to `GameManager.WorldLoaded`; tests / tools call it explicitly). It also works before the window exists (writes the sparse store).
* Props: `IPropLibrary` (`PropLibraries.Current`). `ArtPropLibrary` takes Blender models from `Assets/Game/Art/**` (editor AssetDatabase) or `Resources/Props/<id>`
  and falls back to `ProceduralPropLibrary` stand-ins. `InstancedPropRenderer` draws trees / rocks / reeds with `Graphics.RenderMeshInstanced` (32 m cells, 3 LODs);
  `PropColliderPool` gives colliders within 80 m of the player. Structures (`StructureDef`) become GameObjects (`WorldObjects`), fragile bridges collapse above their load.
* Water: `WaterSurfaceMesh` (isolated stand-in mesh from the raster; replace freely).
* Review tools: `MudRunner.EditorTools.WorldPreview.Map` (no graphics, writes `Captures/world_*.png`), `WorldPreview.Run` (GFX=1, perspective views).
  Tests: `Assets/Game/Tests/PlayMode/WorldTests.cs`.

Known limits: stand-in props are flat-coloured low poly; no LOD billboards; water is a plain transparent quad mesh; ruts in mud relax like player ruts.
