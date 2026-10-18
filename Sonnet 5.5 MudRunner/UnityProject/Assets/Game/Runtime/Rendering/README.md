# Ground renderer (deformable ground)

Draws the whole ground (tested up to 2 km x 2 km, 1 m height samples) with **real geometry displacement + shading** driven by the
CPU-authoritative `MudField` the physics writes. Everything is procedural (no imported textures), hand-written URP HLSL, Forward / Forward+ compatible.

| File | Role |
|---|---|
| `GroundTextures.cs`, `GroundPatterns.cs` | Procedural, tileable texture set (Burst jobs): 8 surface layers (albedo+smoothness array, normal+height array), macro-variation noise, detail normal. ~0.9 s for 1024^2 x 8 in the editor. |
| `GroundMapTextures.cs` | GPU copies of a `GroundMap`: height (R32F), macro normal (RGHalf), 2 control maps (RGBA8), params (RG8: extraDepth, baseWet). |
| `GroundMeshes.cs` | Shared flat grid meshes (LOD0 128x128 = 0.25 m ... LOD4 8x8 = 4 m) with a 2.5 m skirt. |
| `GroundRenderer.cs` | MonoBehaviour: builds resources + 32 m chunks, time-sliced LOD / distance culling. |
| `GroundColliderBuilder.cs` | Runtime `Terrain` used only as a physics collider. |
| `../../Shaders/Ground.shader` + `GroundCommon/GroundForward/GroundPasses.hlsl` | Shader `MudRunner/Ground` (ForwardLit, ShadowCaster, DepthOnly, DepthNormals). |
| `Assets/Editor/Rendering/GroundRenderCapture.cs` | Batch harness that renders the PNGs in `Captures/` and prints measurements. |
| `Resources/MudRunner/GroundMaterial.mat` | Material template (only exists so the shader is included in player builds; the renderer instantiates it). |

## Using it

```csharp
// 1. data + deformation field (GroundService owns Map + MudField and pushes the _MR_* globals)
var gs = TestArena.Install(map, focus: Vector3.zero, wetness: 0.3f);      // or your own GroundService.Initialize(map, 0.25f, focus)

// 2. renderer
var r = new GameObject("GroundRenderer").AddComponent<GroundRenderer>();
r.targetCamera = Camera.main;                    // optional (defaults to Camera.main)
r.Build(map);                                    // creates textures, meshes, chunks   (r.Rebuild() after editing map data)

// 3. physics collider (rocks, logs, cargo - wheels do NOT use it)
Terrain collider = GroundColliderBuilder.Create(map);          // layer Terrain, nothing drawn, never an asset
```

One-call alternative: `var r = GroundRenderer.Create(map, camera, withCollider: true);` (builds chunks and the collider; `r.Collider` holds the Terrain).

Game integration (already wired by `WorldBuilders.Build` + `GameManager.StartWorld`): the world builder creates the collider (`GroundColliderBuilder.Create(map, root)`) and adds a
`GroundRenderer` with `buildFromGroundService = true` under the world root; `GameManager.StartWorld` then creates + initialises the `GroundService`, and the renderer builds itself from the
service map in its `Start()` (or in `Update` if the service appears later) - so the deformable ground shows up automatically. Needs a camera tagged `MainCamera`
(or assign `targetCamera`) and a directional light for shadows. Note: after `Destroy(World.root)` the old renderer still exists until the end of the frame, so any
`FindFirstObjectByType<GroundRenderer>() == null` check in the same frame as a world restart will not create the new one.

With a `GroundService` in the scene and `buildFromGroundService = true` (default) the renderer builds itself in `Start()` and on `GroundService.MapReplaced`,
so `AddComponent<GroundRenderer>()` is enough. The renderer follows `Camera.main` automatically; `GroundRenderer.UpdateLod(true)` forces a full LOD pass
(use after teleports / before screenshots). Per frame it only runs a time-sliced sweep (5 sweeps per second, no allocations).

Public knobs on `GroundRenderer`: `MaxDrawDistance` (0 = camera far plane), `lodDistances` (40/90/180/400 m), `lodHysteresis`, `lodSweepsPerSecond`,
`tileSizeA/B` (texture world sizes, 3.2 / 19.3 m), `normalStrength`, `fieldNormalGain`, `rippleStrength`, `puddleLevelScale`, `skirtDrop`; call `ApplyMaterialSettings()` after changing them at run time.
`GroundRenderer.SetDebugMode(int)` sets the global `_MR_DebugMode`: 0 off, 1 surface-type colours, 2 dh (red = rut, blue = berm), 3 churn, 4 LOD colours, 5 normals.
Stats: `ChunkCount`, `VisibleChunkCount`, `VisibleTriangleCount`, `GetLodChunkCount(lod)`.

`GroundService` was extended minimally: it additionally publishes `_MR_MudWindowOrigin` (xy = world XZ of the field window's min corner).

## How it works

* **Geometry**: the world is split into 32 m chunks anchored on the absolute 32 m grid (shifted by half a field texel so vertices sit on texel centres). Each chunk is one
  `MeshRenderer` using a shared flat grid mesh (y = 0) and the single shared material (SRP Batcher, no `MaterialPropertyBlock`); chunk origin = `unity_ObjectToWorld`.
  The vertex shader reads the macro height texture and adds `dh` from `_MR_MudField` (bilinear), faded to 0 within 12 m of the field-window border.
  Vertices outside the map are clamped onto its border (exact map edge). Skirt vertices (uv.x = 1) drop 2.5 m to hide LOD cracks.
  LODs: LOD0 0.25 m <= 40 m, LOD1 0.5 m <= 90 m, LOD2 1 m <= 180 m, LOD3 2 m <= 400 m, LOD4 4 m beyond; all LODs apply the same displacement so ruts stay visible at distance.
* **Fragment**: control maps (2 x RGBA8) select layers; only layers with weight > 0.02 are sampled; height-based blending sharpens transitions; two texture scales (3.2 m + rotated 19.3 m) and
  two macro-noise octaves break tiling; the cost drops with distance (tile A and normal maps fade out by ~110 m, height-blend by ~100 m). Steep slopes (> ~35 deg) switch to biplanar rock.
  Normal = baked macro normal + field gradient (central differences of dh at +-1 texel) + texture normal + near detail normal; geometric specular anti-aliasing removes glitter.
* **Wetness**: `wet = saturate(baseWet + _MR_Wetness * sensitivity + churn + rut)`; wet = darker, more saturated, glossier, flatter normals. Ruts get dark wet glossy floors, berms are lighter and rougher,
  compaction darkens/smooths the rut floor, churned/rutted soil reveals wet mud of any soft surface (`ShallowMud` / `DeepMud` layers) so ruts on grass show brown mud.
  **Standing water**: ruts deeper than `lerp(0.20 m, 0.022 m, smoothstep(0.35, 0.95, _MR_Wetness + 0.7 baseWet)) + 0.028 m` on flat ground fill with flat, mirror-like, dark water with ripple normals.

## Shader `MudRunner/Ground`

Material properties (set by `GroundRenderer`, SRP-Batcher compatible - all non-texture ones live in `UnityPerMaterial`):
`_GR_Height`, `_GR_NormalMap`, `_GR_Control0/1`, `_GR_Params`, `_GR_Albedo` (2DArray), `_GR_Normal` (2DArray), `_GR_Macro`, `_GR_Detail`,
`_GR_Map` (origin.xy, 1/cell, 1/size), `_GR_MapRange` (min.xy, max.xy), `_GR_Tiling` (1/tileA, 1/tileB, macro scales), `_GR_LayerScale0/1`, `_GR_WetSens0/1`,
`_GR_Misc` (skirt drop, field normal gain, detail scale), `_GR_Misc2` (normal strength, ripple strength, puddle level scale).

Globals read: `_MR_MudField`, `_MR_MudParams`, `_MR_MudWindowOrigin`, `_MR_Wetness` (all from `GroundService`), `_MR_DebugMode` (set with `GroundRenderer.SetDebugMode`).
Keywords: main light shadows (+cascades / screen), additional lights (+shadows, clustered / Forward+), soft shadows, SSAO, reflection probes, light layers / cookies, fog. Lightmaps are not supported.

## Measured (RTX 5070, Direct3D11, editor, 1080p, 400 m showcase map)

(`GFX=1 Tools/ub.sh groundcap MudRunner.EditorTools.GroundRenderCapture.Run` with `GR_ONLY="... perf"`; PNGs go to `Captures/`.)
URP PC asset: Forward+, SSAO (depth normals), 4 soft-shadow cascades, SMAA, ACES - the numbers include all of that.

* Textures: 8 x 1024^2 (albedo+smoothness, normal+height, mips, aniso 8) + macro + detail: ~0.9 s (editor, incl. Burst compile). Map GPU resources + 196 chunks (400 m map): ~0.1 s; 2 km map (4096 chunks): 0.17-0.46 s.
* Geometry: 0.4-0.85 M visible triangles on the 400 m showcase map (LOD0 chunk = 32.8 k tris), 1.06 M on the 2 km map (4096 chunks, camera in the middle).
* Whole-frame Camera.Render CPU ~1.1-1.8 ms (ground chunks add ~0.2-0.8 ms of that).
* GPU (4K, GPU-bound, with/without ground): close view 4.4 ms vs 1.7 ms => ground 2.7 ms at 4K of which ~1.1 ms are the sun shadow cascades; overview 0.8 ms at 4K.
  Pixel-bound estimate for 1080p: ~0.2-0.7 ms plus ~0.3 ms shadows - inside the 1.5 ms budget.
* LOD update: 3.2 us per `UpdateLod(false)` call; a full sweep over 4096 chunks costs 0.30 ms => ~0.025 ms average per frame (60 fps, 5 sweeps/s). **0 bytes** GC allocated per call.
* `GroundColliderBuilder.Create` for a 2 km map (2049^2 heightfield): ~0.6 s.

## Known limits / TODO

* Lightmaps / light probes are not used (ambient SH + reflection probes only); decals (DBuffer) are not supported on the ground shader.
* Heights come from bilinear 1 m samples; steep terrain with high-frequency detail should be authored at finer resolution or smoothed.
* Texture memory ~ 90 MB (uncompressed RGBA32 with mips); a BC7-compressed bake would cut this to ~22 MB.
* The deformation field only exists in the 256 m window around the focus; beyond the border the ground is undisturbed.
* The collider is a heightfield (no overhangs) resampled to 2^n + 1; creating it for a 2 km map takes ~0.7 s.
* Shader variants are compiled by the player build as usual; the first Editor render of each keyword set compiles on demand.
