# -*- coding: utf-8 -*-
"""Generates Docs/Kits/roadside_kit.md from the JSON sidecars in Exports/Roadside (run with plain python, not inside Blender):
    python Tools/blender/roadside/make_doc.py
"""
import json, os, glob, datetime

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..'))
EXP = os.path.join(ROOT, 'Exports', 'Roadside')
OUT = os.path.join(ROOT, 'Docs', 'Kits', 'roadside_kit.md')

GROUPS = [
    ('barrier', 'Barriers, rails, posts and bollards'),
    ('trafficfurniture', 'Traffic furniture (cone, drum, tyres, hay bales)'),
    ('sign', 'Road signs on posts'),
    ('lighting', 'Street / gantry lighting'),
    ('utility', 'Utility poles and wire'),
    ('fence', 'Fences and walls'),
    ('village', 'Village furniture'),
    ('advert', 'Billboard'),
    ('drainage', 'Culvert head-walls'),
    ('mountain', 'Mountain markers'),
]

ASSET_NOTES = {
    'rs_guardrail_4m': 'BODY. Tile every 4.0 m along +X (posts at x=0 and x=2.0, none at x=4.0); traffic face +Y, posts behind (-Y). W-beam top 0.75 m, posts 0.80 m, galvanised C-posts + black composite blocks.',
    'rs_guardrail_end_terminal': 'START of a run: flared (0.32 m) impact head at x=0, bolts onto the first post of a rail at x=4.0. For the END of the same run use _R (rotating 180 deg puts the posts on the road side).',
    'rs_guardrail_end_terminal_R': 'END of a run (mirror-built from the start terminal, winding fixed, no negative scale): joins the previous rail at x=0 with its own joint post + splice bolts, impact head at x=4.0.',
    'rs_guardrail_curved_end': 'END of a run, turned down: joins the previous rail at x=0 (own joint post), leaves the run line after 1.2 m, curves 1.15 m away from the road (-Y) and dives into a concrete ground anchor with steel eye at x=4.2.',
    'rs_guardrail_curved_end_R': 'START of a run, turned down (mirror-built): anchor at x=0, rail returns to the run line and joins the next rail at x=4.2 (the next rail brings the post and bolts at that joint).',
    'rs_parapet_mountain_3m': 'Stone-faced wall (both faces coursed, pier at x=0) + two timber rails. Traffic face y=0, body to -Y. Close the run with rs_parapet_mountain_end.',
    'rs_parapet_mountain_end': 'END of a parapet run: same stone pier as the segment (origin on the far end of the last segment) + 1.0 m stepped wall return that dives into the hillside.',
    'rs_barrier_jersey_3m': 'Symmetric New-Jersey profile 0.78 m (0.82 m with lifting loops), centreline y=0, 3.0 m, grooves every metre, amber reflectors.',
    'rs_bridge_rail_2m': 'Post on origin, round top/mid/low rails + 7 balusters + kick plate, 1.08 m high. Tile every 2.0 m.',
    'rs_delineator_post': 'Reflector (red) faces +X. Variants: _white, _amber.',
    'rs_bollard_stone': 'Granite bollard with painted band, 0.85 m.',
    'rs_bollard_plastic': 'Flexible plastic bollard 0.96 m; give it no collision.',
    'rs_traffic_cone': '0.70 m cone, black base, two reflective collars.',
    'rs_traffic_barrel': 'Channelizer drum 0.95 m, orange/white.',
    'rs_tyre_stack': '4 tyres (white-painted / black alternating, different radius / yaw / tilt): ribbed tread with lug slots, chamfered shoulders, bead lip, raised lettering ring on the top tyre, 2 ratchet straps with buckles seated in the seams.',
    'rs_hay_bale_roadblock': '5 bales with streaky straw vertex colour + straw tufts, twine, red/white warning board; spans Y (2.8 m); front +X.',
    'rs_streetlamp_8m': 'Arm reaches 2.55 m towards +Y. Light socket in sidecar. Lens = M_RS_LampLens (emissive).',
    'rs_gantry_lamp': '10 m pole + 5.7 m cantilever truss towards +Y + 3 flood heads. Light sockets in sidecar.',
    'rs_utility_pole_9m': 'Crossarm along Y; wire attach sockets (wire_L / wire_R / wire_top) in sidecar.',
    'rs_utility_wire_span_30m': 'Origin = pole centreline at insulator-top height: spawn at pole_base + (0, 0, 8.654); 3 conductors start on the insulator tops, 0.70 m sag, end 30 m along +X (next pole). Id requested as utility_wire_span_30m (rs_ prefix added).',
    'rs_utility_wire_span_30m_taut': 'Same placement as rs_utility_wire_span_30m, 0.40 m sag.',
    'rs_utility_wire_span_30m_slack': 'Same placement as rs_utility_wire_span_30m, 1.05 m sag.',
    'rs_fence_wood_2_5m': 'Post (with soil mound) on origin, 3 rails (two overlapping split timbers each) run to the next post; close a run with rs_fence_wood_endpost. _b (rails 8 cm lower) and _c (two rails) share post and envelope.',
    'rs_fence_wood_2_5m_b': 'Variant: three rails at 0.30 / 0.66 / 1.02 m.',
    'rs_fence_wood_2_5m_c': 'Variant: two rails at 0.55 / 1.05 m.',
    'rs_fence_wire_3m': 'Round wooden post on origin + steel T-post at mid span, 5 strands + vertical stays.',
    'rs_wall_stone_2m': 'Dry-stone wall, both faces coursed with pillow-faced stones, 0.55 m thick, centreline y=0.',
    'rs_wall_stone_2m_b': 'Variant B: same envelope / end faces, 5 courses of different heights and stone lengths (alternate with the base segment).',
    'rs_bus_stop_shelter': 'Open/bench side faces +X. Glass = separate M_RS_Glass slot (translucent in UE). Not Nanite (translucent).',
    'rs_billboard_roadside': 'Face (M_RS_BillboardFace, UV 0..1 over whole face) faces +X, preview shows original ad A; ads B / C ship as textures + preview materials; 4 lamp sockets in sidecar.',
    'rs_culvert_headwall_a': 'Round 1.24 m pipe with collar + mortar fillet, 35 deg wing walls, apron, coping with drip step, belt course, weep holes, form ties, ID plate. Opening faces +X. Collision: 4 hulls frame the open mouth + 1 closed wedge per wing.',
    'rs_culvert_headwall_b': 'Box opening 1.8 x 1.24 m with trash rack, stepped wing walls, guard posts + rail, weep holes. Opening faces +X. Collision: frame hulls + one closed hull per wing step / post + thin rack hull.',
    'rs_cairn_stack': 'Eight balanced stones (angular slabs alternating with rounded river stones, per-stone colour) + 9 angular / rounded chips.',
    'rs_milestone_stone': 'Granite slab with painted number plate (12 km) facing +X.',
    'rs_milemarker': 'White plastic km post with green plate; plate faces +X.',
    'rs_speedtrap_camera': 'Camera housing looks along +X; sockets camera_lens / flash in sidecar.',
}

def fmt_dim(d):
    return '%.2f x %.2f x %.2f' % (d['x'], d['y'], d['z'])

def main():
    rows = {}
    for jp in sorted(glob.glob(os.path.join(EXP, 'rs_*.json'))):
        d = json.load(open(jp, encoding='utf8'))
        rows[d['id']] = d
    man = json.load(open(os.path.join(EXP, '_manifest.json'), encoding='utf8'))
    order = [a['id'] for a in man['assets']]
    total_tris = sum(rows[a]['tri_counts']['lod0'] for a in order)
    L = []
    w = L.append
    w('# Roadside kit (Blender -> Unreal)\n')
    w('Generated %s by `Tools/blender/roadside/make_doc.py` from the JSON sidecars. %d assets, %d materials, %d triangles in total (sum of LOD0).\n' % (datetime.date.today().isoformat(), len(order), len(man['materials']), total_tris))
    w('Source of truth: `Tools/blender/roadside/*.py` (idempotent scripts, executed in the shared Blender on port 9889). Binding conventions: `Docs/BLENDER_CONTRACT.md`.\n')
    w('## 1. Files\n')
    w('| What | Path |')
    w('|---|---|')
    w('| Entry point / registry | `Tools/blender/roadside/roadside_kit.py` (execs the parts below into a private namespace) |')
    w('| Library (bmesh primitives, materials, build / validate / export harness) | `Tools/blender/roadside/rs_lib.py`, `rs_font.py` (original stroke font), `rs_ads.py` (billboard artwork generator, numpy) |')
    w('| Builders | `rs_barriers.py`, `rs_barriers2.py`, `rs_traffic.py`, `rs_signs.py`, `rs_poles.py`, `rs_misc.py` |')
    w('| Doc generator | `Tools/blender/roadside/make_doc.py` |')
    w('| FBX + sidecar per asset | `Exports/Roadside/<asset_id>.fbx` + `<asset_id>.json` |')
    w('| Billboard ad textures | `Exports/Roadside/Textures/T_RS_BillboardAd_A/B/C.png` (2048 x 1024, original generic artwork) |')
    w('| Manifest (all assets, one file) | `Exports/Roadside/_manifest.json` |')
    w('| Blender staging | world position `(x_slot, 80, 0)`; collections `FORZA_UE/Roadside/<asset_id>` (mesh + hidden `UCX_*` hulls) |')
    w('')
    w('Rebuild / re-export from the Blender MCP console:\n')
    w('```python')
    w('_p = r"<project>/Tools/blender/roadside/roadside_kit.py"; _g = {"__name__": "rs_kit"}')
    w('exec(compile(open(_p, encoding="utf8").read(), _p, "exec"), _g)')
    w('_g["build"](["rs_guardrail_4m"])        # or _g["build"]() for the whole kit; idempotent')
    w('_g["validate_all"](); _g["export"]("rs_guardrail_4m"); _g["write_manifest"]()')
    w('```\n')
    w('## 2. Conventions\n')
    w('* Units: 1 BU = 1 m, Z up. Blender +X = forward / sign face / run direction. FBX recipe from `Tools/blender/lib/fbx_export.py` (`center_on="self"`, `use_triangles=True` so tangent space exports); in UE: x = x*100, y = -y*100.')
    w('* **Tileable segments** (`pivot: segment_start`) start at the origin and run along **+X** by their documented length. Rails, barriers, parapet and fences have their **traffic face on +Y** (the road lies on the +Y side when walking +X; rotate 180 deg about Z to use the other verge). Jersey barrier, bridge rail and stone wall are centred on y = 0.')
    w('* **Single props** (`ground_centre` / `ground_base`) have the origin on the ground at the base centre (street lamp, gantry lamp and utility pole: origin = pole base; arms/booms reach towards +Y). Culverts and the billboard use the head-wall / post line as origin (`ground_base`). Signs: post axis on the origin, **panel faces +X**, screen-right = +Y.')
    w('* **Guard-rail run convention** (walking +X, road on +Y): `rs_guardrail_end_terminal` = START (free head x=0, flared away from the road, bolts to the next rail at x=4.0); `rs_guardrail_4m` = body (posts at x=0 and 2.0, none at x=4.0); `rs_guardrail_end_terminal_R` = END (joins at x=0, brings its own joint post + splice bolts, head at x=4.0, mirror-built); `rs_guardrail_curved_end` = turned-down END (joins at x=0); `rs_guardrail_curved_end_R` = turned-down START (anchor at x=0, joins at x=4.2). Rotating a piece 180 deg about Z moves it to the opposite verge, it does NOT turn a start piece into an end piece. Parapet: `rs_parapet_mountain_3m` x N + `rs_parapet_mountain_end` at the far end.')
    w('* `rs_utility_wire_span_30m` (+ `_taut` / `_slack`) is the only asset without a ground contact (`pivot: attach_point`): the origin is the pole centreline at insulator-top height, so spawn it at `pole_base + (0, 0, 8.654)` (sidecar `extra.place_at_pole_base_offset`), next pole `extra.next_pole_offset` = (30, 0, 0).')
    w('* Rail / fence / pole posts are embedded 0.15-0.2 m below z = 0 so they can be planted on slopes; everything else sits at z = 0.')
    w('* One mesh object per asset named exactly like the asset id, transforms applied, no parent. Collision = `UCX_<id>_NN` convex hulls (<= 32 verts) exported in the same FBX (Blender hides them in the viewport).')
    w('* UVs: `UVMap` = metric box projection (1 UV unit = 1 m) for tiling materials; cylinders/lathes use arc-length UVs. The billboard face has UV 0..1 over the whole face. Vertex colour `Col` carries per-part tint / dirt (white = neutral) - the tinted materials (Concrete, Wood, Stone, Hay, Rust, Soil) multiply it in Blender; replicate with a VertexColor node in the UE master material.')
    w('* **Decal cards** (sign lettering, pictograms, bands, culvert marks): single-sided flat polygons 1.2-2.4 mm above the plate, tagged with a face attribute `decal` (the only open geometry in the kit; every other island is closed). They are drawn on a +X facing plane and their back is hidden by the plate; the sidecar field `decal_faces` counts them.')
    w('* Shading: per-face smooth flags (FBX `mesh_smooth_type=FACE`). Curved surfaces are smooth, chamfered boxes / flat plates are flat.')
    w('* Max 8 materials per asset (all assets: <= 8, most <= 6). Materials are shared by name `M_RS_*`.\n')
    w('## 3. Assets\n')
    for g, title in GROUPS:
        ids = [a for a in order if rows[a]['group'] == g]
        if not ids:
            continue
        w('### %s\n' % title)
        w('| Asset | Dimensions m (x y z) | Tris | Material slots | Collision | Scale range | Notes |')
        w('|---|---|---|---|---|---|---|')
        for a in ids:
            d = rows[a]
            mats = ', '.join(m.replace('M_RS_', '') for m in d['material_slots'])
            hulls = len(d['collision']['hulls'])
            col = d['collision']['type'] + (' (%d UCX)' % hulls if hulls else '')
            sc = '%.2f-%.2f' % tuple(d['scale_range'])
            note = ASSET_NOTES.get(a, d.get('usage', ''))
            w('| `%s` | %s | %d | %s | %s | %s | %s |' % (a, fmt_dim(d['dimensions']), d['tri_counts']['lod0'], mats, col, sc, note))
        w('')
    w('### Sign family (flat panels with modelled rims, raised borders and geometric pictograms)\n')
    w('Speed limits 30 / 50 / 70 / 90 / 110, curve left / right, hairpin, steep descent (12 %), tunnel, bridge, junction, stop, give way, three blue direction signs (small 1.2 x 0.45 on one post, medium 1.8 x 0.65 and large 2.8 x 1.15 on two posts), village name sign, kilometre marker, chevron boards (left / right), danger-jump diamond + JUMP plate, speed-trap camera post. All symbols and place names (OAKRIDGE, HARBOR, SUMMIT) are original and built from geometry (stroke font in `rs_font.py`, 11-22 segments on round glyphs), nothing is copied from real sign sets. Plates, folded rims and posts are closed solids; borders, lettering and pictograms are single-sided decal cards (see Conventions), which keeps every sign at 0.3-1.3 k triangles. Panel faces +X; all signs share the 7 sign materials (`SignWhite/Red/Black/Blue/Yellow/Green`, `SignBack`) + `GalvSteel`/`GalvDark` for hardware.\n')
    w('## 4. Materials (UE master-material instances are created BY NAME)\n')
    w('| Material | Use |')
    w('|---|---|')
    USE = {
        'GalvSteel': 'zinc-coated steel: rails, posts, rails, tubes (metallic 0.9, rough 0.4)', 'GalvDark': 'dark galvanised hardware: bolts, brackets, bases',
        'Concrete': 'cast concrete (tinted by vertex colour, dirt gradient near the ground)', 'ConcreteDark': 'stained / wet concrete, kerbs, aprons',
        'Wood': 'timber (tinted)', 'WoodPale': 'bench slats', 'Stone': 'granite / dry stone (tinted)', 'Mortar': 'core between stones',
        'PaintWhite': 'white paint / posts / tyres', 'PaintRed': 'red paint', 'PaintBlack': 'black rubber-like plastic, bands, cabinet doors', 'PaintYellow': 'impact head',
        'PaintGrey': 'powder-coated steel (shelter, bridge rail, cabinets)', 'PlasticOrange': 'cone / drum / bollard', 'PlasticWhite': 'delineator posts',
        'Rubber': 'tyres, feet', 'ReflectorRed': 'retro-reflective red (emissive hint)', 'ReflectorWhite': 'retro-reflective white', 'ReflectorAmber': 'retro-reflective amber',
        'SignWhite': 'sign faces / lettering (retro-reflective)', 'SignRed': 'sign red', 'SignBlack': 'sign black', 'SignBlue': 'direction signs', 'SignYellow': 'warning boards',
        'SignGreen': 'km marker plate', 'SignBack': 'folded sign rim and back', 'LampLens': 'LED lens - EMISSIVE (drive from a time-of-day parameter)',
        'Insulator': 'ceramic pin insulators', 'Glass': 'shelter glass - TRANSLUCENT', 'Hay': 'straw (tinted)', 'Wire': 'fence / power wire', 'Rust': 'trash rack, rebar eyes',
        'BillboardFace': 'billboard face (UV 0..1), preview = ad texture A; swap the texture per material instance', 'Rope': 'bale twine', 'PlasticGrey': '(reserved)', 'Grating': 'catwalk grating', 'Soil': 'soil mound at post feet (tinted)',
        'BillboardFace_B': 'alternative billboard face (ad B) - preview material only, not on the mesh', 'BillboardFace_C': 'alternative billboard face (ad C) - preview material only, not on the mesh',
        'TyreRubber': 'tyre rubber (tinted, dirt gradient near the ground)', 'TyrePaint': 'white tyre paint (tinted, scuffs)',
    }
    for m in man['materials']:
        k = m.replace('M_RS_', '')
        w('| `%s` | %s |' % (m, USE.get(k, '')))
    w('')
    w('## 5. Recommended Unreal setup\n')
    w('* **Static meshes**: enable Nanite for everything except `rs_bus_stop_shelter` (translucent glass slot). Mobility Static. Import with *Auto Generate Collision = off* - the `UCX_*` hulls come with the FBX. `collision: none` assets (delineator posts, flexible bollard, wire fence panel + strainer assembly, wire span) ship without UCX hulls and should have no collision; use *Simple* collision only for the rest.')
    w('* **Instancing**: tile rails / barriers / fences / walls as splines or HISM runs at the documented segment length. Recommended placement spacing: guard rail 4.0 m, jersey 3.0 m, parapet 3.0 m, bridge rail 2.0 m, wood fence 2.5 m, wire fence 3.0 m, stone wall 2.0 m, delineators 25-50 m, street lamps 30-45 m (alternate sides on dual carriageways), utility poles 30 m (wire span 30 m, scale X by 0.9-1.1 and re-aim to bridge the gap), speed-limit / warning signs 2-4 m from the road edge, km markers every 1 km, chevron boards every 8-15 m in bends.')
    w('* **Scale range** per asset is in the table (rails / signs 1.0 only; props 0.9-1.15; culverts / billboard 0.9-1.4).')
    w('* **Emissive**: `M_RS_LampLens` (street lamp, gantry, shelter light strip / light box, billboard lamps) and the `M_RS_Reflector*` slots should be driven by headlight / time-of-day parameters. Light sockets (spot light origin) are listed per asset in the sidecar `sockets`.')
    w('* **Wind**: none (no vegetation); the wire span can optionally get a tiny WPO sway on the vertical axis.')
    w('* **Colour grading**: vertex colour `Col` is neutral white on non-tinted parts; keep it enabled in the master material.\n')
    w('## 6. Validation (run in Blender, `validate_all()`)\n')
    w('Every asset passes: object / collision names, transforms applied, no parent, ground / pivot rule, <= 8 material slots with `M_RS_*` names and none unused, `UVMap` present with no degenerate (zero-area) UV face, no loose vertices, no zero-area faces, all solid islands closed (open boundaries are allowed only on tagged decal cards), no inverted islands (signed-volume test), triangle budget per asset, and every `UCX_*` hull is a closed, convex, positive-volume mesh with <= 32 vertices (flat quads / open shells are rejected by the validator). Largest meshes: ' +
      ', '.join('`%s` %d' % (a, rows[a]['tri_counts']['lod0']) for a in sorted(order, key=lambda k: -rows[k]['tri_counts']['lod0'])[:6]) + ' tris.\n')
    w('## 7. Known weaknesses\n')
    w('* Sign graphics are single-sided decal cards 1.2-2.4 mm above the plate (no relief sides): crisp and original, but at grazing angles / very close the card edge shows a hairline gap, and the retro-reflective response must come from the UE material (`SignWhite/Red/...` need a clear-coat / emissive-at-night term).')
    w('* Stonework (parapet, wall, cairn, bollard, milestone) is pillow-faced frustum blocks / pebbles with vertex-colour tint; the fine surface detail must come from a tiling UE stone material (UV is metric).')
    w('* Tyre stack: black rubber barely shows its tread in a flat preview (needs normal / AO in UE); painted tyres expose rubber in the grooves and lug slots; there are 10-12 lug slots per tyre (30 / 36 radial segments) and the lower three tyres have a simplified hidden sidewall. 5.1 k triangles (budget 5.2 k) makes it the heaviest asset of the kit.')
    w('* Hay bales: lumpy low-poly shells with streaky vertex colour and ~30 straw tufts each, no real straw cards / fuzz; M_RS_Hay still wants a UE straw texture.')
    w('* Fence wire, stays and the power wires are 3-8 mm geometry: they alias without Nanite + TSR. A masked-card far version for non-Nanite platforms is NOT provided (it needs an alpha-masked UE material).')
    w('* Guard-rail pieces butt-joint (4 splice bolts, no real lap overlap). The handed pieces are mirror-built copies: for a run on the opposite verge rotate the whole run 180 deg about Z, never mirror.')
    w('* Utility wire spans have a fixed sag (0.40 / 0.70 / 1.05 m variants); non-uniform scaling changes the sag proportionally.')
    w('* Billboard: three original ad textures ship, the Blender mesh carries ad A only (ads B / C are separate preview materials: swap per UE material instance). The shelter poster / light box is still a flat emissive panel.')
    w('* No hand-made LODs (Nanite assumed). `rs_bus_stop_shelter` (translucent glass slot, 7 material slots) needs classic LODs if it must be placed in great numbers; a lighter proxy for the stone wall / parapet is not provided.')
    w('* Culvert aprons and pipe interiors carry no collision (drive-over / pass-through by design); the pipe mouth is framed by hulls, so the 1.24 m square opening is slightly larger than the round bore.')
    w('* Triangle budgets: every asset is within its registered budget; the sign set (0.3-1.3 k) is inside the 0.2-2 k sign budget and the guard-rail pieces are <= 1.5 k. Only the tyre stack (5.1 k) and hay roadblock (2.6 k) sit above the generic 2 k prop figure on purpose.')
    w('* Asset ids use the `rs_` prefix; the brief name `utility_wire_span_30m` is `rs_utility_wire_span_30m`.')
    w('')
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    open(OUT, 'w', encoding='utf8').write('\n'.join(L))
    print('wrote', OUT, len(L), 'lines')

if __name__ == '__main__':
    main()
