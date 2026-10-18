# Nature + FX materials (masters, instances, parameters)

Companion of `Docs/Tech/MATERIALS.md` (roads / buildings / roadside / server / MPC). Everything here is built by the same one command
(`Tools/ue/materials_build.py`, steps `masters` and `instances`) and is idempotent. Source files:

| file | what |
|---|---|
| `Tools/ue/materials_m_nature.py` | masters `M_Roam_Foliage_Masked`, `M_Roam_Bark`, `M_Roam_Grass_Blade`, `M_Roam_Flower`, `M_Roam_Rock`, `M_Roam_Tree_Far` |
| `Tools/ue/materials_m_fx.py` | masters `M_Roam_Water_Simple`, `M_Roam_Water_River`, `M_Roam_Particle_Soft`, `M_Roam_Particle_Unlit`, `M_Roam_Skid`, `M_Roam_PP_Rain` |
| `Tools/ue/materials_instances.py` | instance registry + nature instances; writes `Tools/ue/materials_slot_map.json` (Blender slot name -> MI asset path) |
| `Tools/ue/materials_instances_fx.py` | water / glass / particle / decal instances |
| `Tools/ue/materials_testsheet_nature.py` | test-sheet stations `trees`, `ground`, `treemesh`, `cover`, `evcal` (run through `Tools/ue/materials_sheet.py`) |

All masters read the global weather / wind collection `MPC_Roam_World` (Wetness, SnowAmount, DustAmount, WindDirection, WindStrength, WindSpeed,
FoliageSeason, SeasonTint, TimeOfDay, NightFactor, ...). A material instance never needs to be touched for weather: drive the MPC.

## Slot -> instance (the importer binds by Blender slot name)

`Tools/ue/materials_slot_map.json` is the authoritative table (`{"M_Tree_Bark": "/Game/Forza/Materials/Instances/MI_Tree_Bark", ...}`). Nature slots:

| Blender slot | instance | master | look |
|---|---|---|---|
| `M_Tree_Bark` | `MI_Tree_Bark` | `M_Roam_Bark` | oak / pine / palm / olive / poplar trunks (`tree_bark_a`) |
| `M_Tree_Bark_Birch` | `MI_Tree_Bark_Birch` | `M_Roam_Bark` | white paper bark (`birch_bark`) |
| `M_Tree_Bark_Dark` | `MI_Tree_Bark_Dark` | `M_Roam_Bark` | birch trunk foot, dark bark (`tree_bark_b`, tinted down) |
| `M_Tree_Dead` | `MI_Tree_Dead` | `M_Roam_Bark` | bleached dead wood, low saturation |
| `M_Tree_Leaf` | `MI_Tree_Leaf` | `M_Roam_Foliage_Masked` | broadleaf twig cards (oak, poplar), `leaf_atlas_broadleaf` cells 12..15 |
| `M_Tree_LeafLight` | `MI_Tree_LeafLight` | same | yellow-green foliage (birch, poplar) |
| `M_Tree_LeafDry` | `MI_Tree_LeafDry` | same | grey-olive foliage (olive, scrub), no seasonal shift |
| `M_Tree_Needle` | `MI_Tree_Needle` | same, `needle_atlas` | spruce / pine / cypress |
| `M_Tree_Palm` | `MI_Tree_Palm` | same, `palm_frond_atlas` | coconut / date fronds, strong sway |
| `M_Tree_Far_<tree id>` | `MI_Tree_Far_<tree id>` | `M_Roam_Tree_Far` | distance cards (one per tree id, texture `T_<id>_Far` from `Exports/Nature/Trees/Textures`) |
| `M_Rock` | `MI_Rock` | `M_Roam_Rock` | grey granite, triplanar |

Extra instances (no Blender slot, assign by hand / by the scatter system): `MI_Rock_Mossy`, `MI_Rock_Cliff` (sedimentary, 8 m tile),
`MI_Rock_RedClay`, `MI_GrassCards_Green`, `MI_GrassCards_Dry` (atlas cards for landscape grass; the Blender slot `M_Grass_Dry` is `MI_Grass_Dry`, see the ground-cover section), `MI_Flower_Mixed`, `MI_Flower_Daisy|Poppy|Lavender|Buttercup`.

## M_Roam_Foliage_Masked (also the base of grass / flower)

Masked, two-sided, shading model *Two Sided Foliage* (translucency of leaves through `TranslucencyAmount` / `TranslucencyColor`).
Mesh contract (Docs/Kits/nature_trees.md): vertex colour R = branch flex, G = leaf flutter, B = baked AO.

* **Atlas:** textures `AtlasBC`, `AtlasN`, `AtlasORM` (alpha of BC = coverage); `AtlasColumns` x `AtlasRows`; cell index counts row-major from the top left.
* **Tree cards (`StripMode` = 1):** each leaf element uses ONE of FOUR U strips (u in [k/4, (k+1)/4]); strip k shows cell `AtlasFirstCell + (k mod StripCellCount)`.
  `AtlasFirstCell` 12 = last row of the broadleaf atlas, 0 for needles / palms; `StripCellCount` = number of distinct cells available (palms: 2).
* **Plain cards (`StripMode` = 0, grass / flowers, UV 0..1 over the card):** `AtlasCell` fixed cell, or `RandomCells` = 1: cell picked per instance
  (`PerInstanceRandom`) from `[AtlasFirstCell, AtlasFirstCell + CellCount)`.
* **Colour:** `Tint`, `VariationTintA/B` mixed by `VariationAmount` (per instance + noise `PatchVariation`), `StripVariation` (per strip), `SeasonAmount`
  (how strongly MPC `FoliageSeason` / `SeasonTint` shifts it), `NormalStrength`, `RoughnessScale`, `SpecularBase`, `AOStrength`, `HeightAOGradient` (grass).
* **Weather:** `WetnessResponse`, `SnowResponse` (snow dusts the top-facing side).
* **Fade:** `FadeStartDistance` / `FadeEndDistance` (metres; grass and flowers dither out, trees do not).
* **Wind** (vertex stage, shared by bark): `SwayAmplitude` (cm, branch R^2), `FlutterAmplitude` (cm, vertex colour G), `SwayFrequency`, `FlutterFrequency`,
  `WindEnabled`; with `WindMaskFromUV` = 1 the sway weight is the card height (1 - V), for grass without vertex colours. Direction / strength / speed from MPC.
  Max WPO displacement is limited to 140 cm.

## M_Roam_Bark

Nanite compatible. `BaseColorTex`, `NormalTex`, `ORMTex`; `UVScaleU` / `UVScaleV` convert the kit's UV (1 unit = 2 m of trunk) to the texture tile
(1.667 for 1.2 m textures, 2.0 for the 1.0 m birch texture). `Tint`, `VariationTintA/B`, `VariationAmount`, `PatchVariation`, `Saturation`, `NormalStrength`,
`RoughnessScale`, `SpecularBase`, `AOStrength` (+ vertex colour B), `WetnessResponse`, `SnowResponse` (snow on top-facing surfaces) and the wind params above.

## M_Roam_Rock

Triplanar world projection: `BaseColorTex`, `NormalTex`, `ORMTex`, `TileMetres`, `BlendSharpness`, `MacroVariation`, `NormalStrength`, `RoughnessScale`,
`AOStrength`, `Tint`. Slope moss (`MossEnabled`, `MossAmount`, `MossMinUpFacing`, `MossBreakup`, `MossColor`), `SnowResponse` / `SnowColor`,
`DustColor`, `WetnessResponse`. World-space normals (the material uses world normals, so rotate rock meshes freely).

## M_Roam_Tree_Far

Two crossed cards: `CardTex` (baked colour + alpha, masked at 0.33), `Tint`, `Roughness`, `Specular`; darkens slightly with MPC Wetness.

## Water (materials_m_fx.py)

`M_Roam_Water_Simple` (sea / lakes) and `M_Roam_Water_River`: Single Layer Water when it compiles, otherwise a depth-faded translucent surface.
Parameters: `FlowSpeed`, `TileMetresA/B`, `NormalStrength`, `WaveWeightA/B/C`, `UseMeshUV` (river meshes: UV V = along the flow), `FlattenStartMetres` /
`FlattenEndMetres` (waves flatten with distance), `WhiteCapAmount` / `WhiteCapThreshold`, colours `ShallowColor`, `DeepColor`, `FoamColor`, and for SLW
`ScatteringColor`, `AbsorptionColor`, `DensityScale` (translucent fallback: `DepthScaleCm`). Wind (MPC WindDirection) steers the waves, rain adds ripples.

| instance | use |
|---|---|
| `MI_Water_Sea` | open sea, default |
| `MI_Water_Lake` | calm lake, teal |
| `MI_Water_Pond` | small green pond |
| `MI_Water_River` | river / stream |
| `MI_Water_River_Muddy` | brown river |

## Particles, decals, glass

* `M_Roam_Particle_Soft` (lit, volumetric non-directional) and `M_Roam_Particle_Unlit`: `SpriteTex` (alpha = coverage), `Tint`, `OpacityScale`, `SoftDepthCm`
  (soft depth fade), `NearFadeCm`, `UseParticleColor` (Niagara colour x tint), `SelfGlow` (lit) / `Brightness` (unlit). Used by Niagara sprite emitters.
  Instances: `MI_Particle_Dust`, `_Dust_Light`, `_Smoke`, `_Smoke_Tyre`, `_Spray`, `_Snow`, `_Smoke_Unlit`, `_Spark` (additive).
* `M_Roam_Skid` deferred decal (box 0.4 m wide, long axis = decal Y): `MarkBaseColorTex/NormalTex/ORMTex`, `TilesAlong` (decal length / texture tile),
  `Opacity` (runtime fade-out), `OpacityScale`, `NormalStrength`, `RoughnessScale`, `EdgeFade`. Instances: `MI_Skid_Tire` (rubber on asphalt), `MI_Skid_Dirt`.
* Glass: `MI_RS_Glass` (bus shelter) and `MI_Glass_Tinted` are instances of `M_Roam_Glass_Building` with the window grid switched off.

## Test sheet

```
powershell -NoProfile -ExecutionPolicy Bypass -File Tools/ue/materials_job.ps1 Tools/ue/materials_sheet.py -Args0 "trees,ground"
```

builds `L_MaterialTest` (flat shapes, sun + sky) and writes `Saved/MatShots/<shot>.png` over the next minutes (log markers `MAT_SHEET_SHOT`, `MAT_SHEET_DONE`).
Shots: `trees_dry|wet|snow|autumn|close_leaf|close_bark`, `ground_dry|wet|snow|rocks` (plus `road_*` from the road station). Pass `save` in the list to keep the map.


## Ground-cover kit (`Exports/Nature/Cover/nat_*.fbx`, `Docs/Kits/ground_cover.md`): `M_Roam_Foliage_Solid` + instances

The kit models leaves, blades, petals and cactus parts as real geometry (no atlas), vertex colour `Col` = R flex, G flutter, B AO, **A per-element random**.
`M_Roam_Foliage_Solid` (opaque, two sided, Two Sided Foliage, Nanite, WPO wind) takes colour parameters instead of an atlas: `BaseColor`, `Roughness`, `SpecularBase`, `Metallic`,
`VariationTintA/B` + `VariationAmount` (hue / brightness per element from vertex colour A, `UseVertexRandom` 1; 0 = per instance), `PatchVariation`, `SeasonAmount`, `AOStrength`
(vertex colour B), `TranslucencyAmount/Color`, `WetnessResponse`, `SnowResponse`, wind group as the foliage master (`WindEnabled` 0 for fruit, spines, beach props).
Every slot of the kit has an instance named `MI_<slot without M_>` (all `M_*` slots of `Exports/**/*.json` are mapped: `materials_check_slots.py`):

| slots | master | how |
|---|---|---|
| `M_Bush_Leaf`, `_Evergreen`, `M_Bush_Dry`, `M_Bush_Berry`, `M_Cactus`, `_Spine`, `_Fruit`, `M_Grass_Blade`, `M_Grass_Dry`, `M_Reed`, `M_Reed_Head`, `M_Flower`, `_B`, `_Center`, `M_Crop`, `M_Crop_Ear`, `M_Hay_Twine`, `M_Beach_Red/White/Blue/Metal`, `M_Sign_Paint` | `M_Roam_Foliage_Solid` | `BaseColor` = the linear Blender colour (`gc_lib.py`), roughness from the Blender table, sway amplitude per family |
| `M_Rock_Slate`, `M_Rock_Sandstone`, `M_Rock_SandstoneDark`, `M_Rock_Beach`, `M_Sand`, `M_Crop_Soil`, `M_Hay` | `M_Roam_Rock` (triplanar) | texture set tinted to the Blender colour (`tint_for`): rock_grey / rock_cliff (8 m tile, strata) / beach_sand / farmland_soil / grass_dry (hay), moss off |
| `M_Wood_Log`, `M_Wood_LogEnd`, `M_Wood_Plank` | `M_Roam_Bark` | tree_bark_a / wood_planks_weathered tinted to the Blender colour, UV scale for the kit's box projection (2 m per UV unit), wind off |

Test: station `cover` (`materials_sheet.py -Args0 cover`) imports 12 kit meshes and dresses them through the slot map.
