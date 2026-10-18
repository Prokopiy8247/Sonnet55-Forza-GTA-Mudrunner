"""make_ground_cover_doc.py - plain python (no Blender): builds Docs/Kits/ground_cover_kit.md (+ground_cover.md copy) from Exports/Nature/Cover/*.json"""
import json, os, glob
PROJECT = r"W:\YouTube\Claude Sonnet 5.5\Forza Horizen\Sonnet55Forza\UnrealSonnet55Forza"
D = os.path.join(PROJECT, 'Exports', 'Nature', 'Cover')
js = {}
for p in sorted(glob.glob(os.path.join(D, 'nat_*.json'))):
    j = json.load(open(p, encoding='utf8')); js[j['id']] = j
SECTIONS = [
    ('Bushes and shrubs', ['nat_bush_leafy_a', 'nat_bush_leafy_b', 'nat_bush_leafy_c', 'nat_shrub_evergreen_a', 'nat_shrub_evergreen_b', 'nat_bush_tumble']),
    ('Rocks - granite boulders (rounded)', ['nat_rock_granite_a', 'nat_rock_granite_b', 'nat_rock_granite_c']),
    ('Rocks - jagged mountain rocks', ['nat_rock_jagged_a', 'nat_rock_jagged_b', 'nat_rock_jagged_c']),
    ('Rocks - sandstone mesa chunks (real strata geometry, 2 materials)', ['nat_rock_mesa_a', 'nat_rock_mesa_b', 'nat_rock_mesa_c']),
    ('Rocks - coast / beach rocks', ['nat_rock_coast_a', 'nat_rock_coast_b', 'nat_rock_coast_c']),
    ('Cliff formations (canyon + coast)', ['nat_cliff_canyon_a', 'nat_cliff_coast_b']),
    ('Cacti', ['nat_cactus_saguaro_a', 'nat_cactus_saguaro_b', 'nat_cactus_barrel', 'nat_cactus_pricklypear']),
    ('Grass, flowers, reeds', ['nat_grass_lush', 'nat_grass_dry', 'nat_grass_reeds_tall', 'nat_flowers_a', 'nat_flowers_b', 'nat_reeds_a', 'nat_reeds_b']),
    ('Farm: crops and hay', ['nat_crop_wheat_row', 'nat_hay_round', 'nat_hay_stack']),
    ('Wood', ['nat_logpile', 'nat_log_fallen', 'nat_stump']),
    ('Beach props and signage', ['nat_beach_umbrella', 'nat_beach_lounger', 'nat_beach_towel_ball', 'nat_beach_bucket', 'nat_sign_arrow']),
]
L = []
A = L.append
A('# Ground cover kit (bushes, rocks, cliffs, cacti, grass, crops, wood, beach props)\n')
A('Generator: `Tools/blender/nature/ground_cover.py` (+ `gc_lib.py`, `gc_rocks.py`, `gc_plants.py`, `gc_misc.py`), idempotent, runs in the shared Blender 5.2 session. Docs generator: `Tools/blender/nature/make_ground_cover_doc.py`.')
A('Exports: `Exports/Nature/Cover/<id>.fbx` + `<id>.json` (one FBX per asset, `fbx_export.export_fbx(..., center_on="self")`, UCX hulls included, pivots = base centre at ground). Machine-readable QA: `Exports/Nature/Cover/validation_report.json`.\n')
A('Staging in the master .blend: collection `FORZA_UE/Nature/Cover`, row y = 60 m, starting x = 1200 m (tree row occupies x = 400..1100), assets spaced by footprint.\n')
tot = sum(j['tri_counts']['mesh'] for j in js.values())
A('%d assets, %d tris in total. All assets: origin = base centre on the ground (z = 0, rocks sunk 3-5 cm), +Z up, +X front, transforms applied, UVMap present, vertex colour `Col` present.\n' % (len(js), tot))
A('## Conventions\n')
A('* Vertex colour `Col` (FBX exported LINEAR): **R** = flex (0 at root / ground, 1 at tips and outer shell), **G** = flutter (0 stem, 1 free leaf/blade tips), **B** = baked AO-like occlusion (1 = open), **A** = per-element random 0-1 (hue / phase variation per leaf, blade or flower). Rocks/cliffs/wood: only B (AO) is meaningful.')
A('* Foliage (`wind: true` in the JSON) is modelled geometry (leaf shapes, blades, petals) - no alpha cards needed, Nanite friendly; use **two-sided** materials for leaves, blades and petals. Tufts/blades have no custom normals (smooth by face).')
A('* UVs: foliage elements map 0-1 per leaf/blade (u across, v along); rocks, bales and bark use box projection at 2 m per UV unit (tiling textures); no atlas.')
A('* Collision: `UCX_<id>_NN` convex hulls (<= 24 verts, verified convex) for solid assets only (rocks, cliffs, cacti trunks, bales, logs, stump, pole, sign post). No collision on foliage, grass, flowers, reeds, crops, towel. UE: Collision Complexity = Use Simple As Complex.')
A('* Materials (Blender names = UE material instance names): `M_Rock`, `M_Rock_Slate`, `M_Rock_Sandstone`, `M_Rock_SandstoneDark`, `M_Rock_Beach`, `M_Bush_Leaf`, `M_Bush_Leaf_Evergreen`, `M_Bush_Dry`, `M_Bush_Berry`, `M_Wood_Log`, `M_Wood_LogEnd`, `M_Wood_Plank`, `M_Cactus`, `M_Cactus_Spine`, `M_Cactus_Fruit`, `M_Grass_Blade`, `M_Grass_Dry`, `M_Reed`, `M_Reed_Head`, `M_Flower`, `M_Flower_B`, `M_Flower_Center`, `M_Crop`, `M_Crop_Ear`, `M_Crop_Soil`, `M_Hay`, `M_Hay_Twine`, `M_Beach_Red/White/Blue/Metal`, `M_Sand`, `M_Sign_Paint`, `M_Metal_Galv`. Max 4 slots per asset. Blender previews use procedural noise tints x vertex AO; UE recreates them by name.\n')
for title, ids in SECTIONS:
    A('## ' + title + '\n')
    A('| id | size X x Y x Z (m) | tris | material slots | collision | scale range | biome tags |')
    A('|---|---|---|---|---|---|---|')
    for i in ids:
        j = js.get(i)
        if not j: A('| %s | (missing) | | | | | |' % i); continue
        d = j['dimensions']
        col = ('%d x UCX' % len(j['collision']['ucx_hulls'])) if j['collision']['ucx_hulls'] else 'none'
        A('| `%s` | %.2f x %.2f x %.2f | %d | %s | %s | %.1f-%.1f | %s |' % (i, d['x'], d['y'], d['z'], j['tri_counts']['mesh'], ', '.join('`%s`' % m for m in j['material_slots']), col, j['scale_range'][0], j['scale_range'][1], ', '.join(j['biome_tags'])))
    A('')
    for i in ids:
        j = js.get(i)
        if j: A('* `%s` - %s. %s' % (i, j['display_name'], j['collision']['notes']))
    A('')
A('## Recommended UE usage\n')
A('* Rocks / cliffs: static meshes with Nanite ON, Use Simple As Complex, random yaw, scale within the listed range (non-uniform scale up to +-10 % for variety), sink 5-20 cm into terrain. Use `M_Rock*` instances with a rock tiling texture; the Blender previews only carry procedural tints.')
A('* Bushes / grass / flowers / reeds / wheat: foliage-actor or PCG instances, no collision, two-sided foliage material, WPO driven by `Col`: sway = R^2 * low-frequency wind, flutter = G * high-frequency noise, darken by lerp(0.35, 1, B), hue-shift by A. Cull distance ~60-120 m (grass tufts ~40 m); no far-card impostors were generated for this group (bushes/grass are cheap modelled geometry; see weaknesses).')
A('* `nat_crop_wheat_row`: 4.0 m tileable along +X (origin at the start of the row centreline) - place end to end with 0.9-1.1 m row spacing; rotate around Z per field.')
A('* Cliffs: place as hero kit pieces at canyon walls and coast; combine 2-3 copies with different yaw/mirroring and blend the base with terrain/scatter rocks. Origin = footprint centre, cliff face toward -Y.')
A('* Beach props: static meshes without Nanite requirements; umbrella collision is the pole only.\n')
A('## Known weaknesses\n')
A('* Granite and coast rocks are smooth soft-polyhedra (fbm + weathering cracks), good at game distance but they rely on the UE rock material/normal map for micro detail; they are flat-bottomed and expect partial burial.')
A('* Cliff faces are a heightfield-style shell (48 x 30 grid per side) with two strata materials: at close range the quad faceting shows; they have no overhang caves and a simple closed back. Scree stones are small separate lumps without collision.')
A('* Bushes: single-sided oriented leaves (4 tris each) read well from > 3 m; close-ups show uniform leaf shapes. Twigs are thin 4-5 sided tubes. No far-LOD card meshes (`_Far`) were produced; rely on Nanite/foliage culling or add impostors later.')
A('* Grass/reeds are flat blade strips (3-5 segments) without custom up-normals; very dense scattering will need LOD/culling. Flower petals are flat quads with a slight cup.')
A('* Cacti spines are tiny tri fans on rib crests (visible only < 5 m); saguaro arms do not collide. Prickly pear pads are simple discs.')
A('* Wood: bark is geometry noise + procedural material only; log end rings are a material tint, not carved geometry (the stump top has modelled growth-ring steps).')
A('* Text on the sign post is not modelled (arrow glyph only). Beach towel is a single sheet (no thickness). Sandcastle is a simple stylised cluster.')
A('* Not individually hand-iterated 3x per asset (speed brief): one build + one visual pass per family; remaining polish candidates: cliff overhangs, rock moss/lichen masks (use vertex colour B), per-leaf normal bending for bushes.')
text = '\n'.join(L) + '\n'
os.makedirs(os.path.join(PROJECT, 'Docs', 'Kits'), exist_ok=True)
for name in ('ground_cover_kit.md', 'ground_cover.md'):
    open(os.path.join(PROJECT, 'Docs', 'Kits', name), 'w', encoding='utf8').write(text)
print('doc written', len(js), 'assets', tot, 'tris')
