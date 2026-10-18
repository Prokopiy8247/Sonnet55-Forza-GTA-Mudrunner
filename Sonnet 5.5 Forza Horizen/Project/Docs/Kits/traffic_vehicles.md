# Traffic vehicles 01-06 (Blender -> UE5.8 kit notes)

Six civilian traffic vehicles for the open world: a compact hatch, a panel van, a 3-axle box lorry, a 12 m coach, a farm tractor and an
old work pickup. Built with the shared car kit (`Tools/blender/lib/carkit.py`, untouched) plus the traffic extension
`Tools/blender/lib/carkit_ext_traffic.py` and the validator / exporter `Tools/blender/lib/traffic_export.py` (variable wheel count).
All follow `Docs/BLENDER_CONTRACT.md` (+X forward, +Y left, +Z up, origin on the ground under the middle of the wheelbase, one FBX per
part, `<id>.json` sidecar, `UCX_*` hulls inside the Body FBX). Everything is original (no manufacturer names, badges or copied models).

| # | Id | Display name | Drivetrain | Wheels | Silhouette |
|---|----|--------------|-----------|--------|-----------|
| 1 | `traffic01_compact` | City Compact | FWD | 4 | small rounded 5-door hatch, 3.63 m |
| 2 | `traffic02_van` | Panel Van | FWD | 4 | high-roof delivery van, sliding door on the right, roof rack |
| 3 | `traffic03_lorry` | Box Lorry | 6x2 (axle 1 driven, axle 2 = undriven tag) | 10 (single front, 2 x dual rear) | cab-over-engine cab + aluminium-post box body, 8.5 m |
| 4 | `traffic04_bus` | Intercity Coach | RWD | 6 (single front, dual rear) | 12 m coach, window band, luggage bays, roof AC pods |
| 5 | `traffic05_tractor` | Farm Tractor | 4WD | 4 (0.48 m front, 0.80 m lugged rear) | bonnet + glazed cab, huge rear fenders, hitch |
| 6 | `traffic06_pickup` | Work Pickup | RWD | 4 | old single cab, slab fenders, open bed, headache rack, rust patches |

## 1. Files

| What | Path (relative to the project root `UnrealSonnet55Forza\`) |
|---|---|
| Build scripts (idempotent; stages `geometry` / `uv_a` / `uv_b` / `uv_wheels` / `validate` / `export`) | `Tools/blender/traffic/traffic0N_<name>.py` |
| Stage driver, QA-light cleanup, save, manifest | `Tools/blender/traffic/traffic_kit.py` (`run(ids, stages)`, `qa_off()`, `save()`, `write_manifest()`) |
| Library (section loft, window cutters, wheels with 1..n axles, seats, hulls, domed lamps, ...) | `Tools/blender/lib/carkit_ext_traffic.py` |
| Validator + FBX/JSON exporter | `Tools/blender/lib/traffic_export.py` (`traffic_validate`, `traffic_export`) |
| FBX + sidecar per vehicle | `Exports/Traffic/<id>/<id>_Body.fbx` (+ `UCX_<id>_Body_NN`), `_Glass.fbx`, `_Interior.fbx`, `_Wheel_<key>.fbx`, `<id>.json` |
| Manifest of all six | `Exports/Traffic/_manifest.json` (written by `write_manifest()` from the sidecars) |
| Blender collections | `FORZA_UE/Traffic/<id>` (root empty `<id>_ROOT` at x = 14 * index m, y = 30 m) |

Re-run in the Blender MCP (every stage < 20 s; geometry < 1 s, UV stages 2-8 s each, validate 2-5 s, export about 1 s):
```python
import os, bpy
_p = os.path.join(os.path.dirname(bpy.data.filepath), "Tools", "blender", "traffic", "traffic_kit.py")
exec(compile(open(_p, encoding="utf8").read(), _p, "exec"), globals())
run(["traffic04_bus"], ["geometry", "uv_a", "uv_b"])          # split: the whole chain of a big vehicle can exceed 20 s
run(["traffic04_bus"], ["uv_wheels", "validate", "export"])
write_manifest(); save()
```

## 2. Dimensions, wheels, triangles (LOD0, from the sidecar JSONs)

| | Compact | Van | Lorry | Coach | Tractor | Pickup |
|---|---|---|---|---|---|---|
| Length x width x height (m) | 3.63 x 1.62 x 1.62 | 5.44 x 2.00 x 2.46 | 8.53 x 2.50 x 3.61 | 12.04 x 2.55 x 3.62 | 4.19 x 2.30 x 2.86 | 5.06 x 1.86 x 2.05 |
| Width incl. mirrors (m) | 1.82 | 2.54 | 3.09 | 3.13 | 2.40 (fenders) | 2.26 |
| Wheelbase (m) | 2.35 | 3.20 | 5.20 (front axle to the middle of the tandem) | 6.10 | 2.35 | 3.10 |
| Track F / R (m) | 1.40 / 1.38 | 1.70 / 1.70 | 2.04 / 1.86 | 2.05 / 1.83 | 1.60 / 1.80 | 1.52 / 1.50 |
| Wheel radius (m) | 0.295 | 0.343 | 0.50 | 0.52 | 0.48 front / 0.80 rear | 0.37 |
| Wheel width (m, measured = ROOT = JSON) | 0.183 | 0.223 | 0.30 front / 0.28 rear | 0.295 | 0.26 front / 0.50 rear | 0.243 |
| Ride height (m) | 0.15 | 0.31 | 0.62 | 0.42 | 0.40 | 0.30 |
| Tris Body | 12 378 | 13 960 | 15 152 | 14 958 | 7 128 | 11 082 |
| Tris Glass | 104 | 48 | 48 | 368 | 96 | 64 |
| Tris Interior | 1 124 | 992 | 992 | 1 736 | 828 | 768 |
| Tris per wheel | 2 058 | 2 320 | 1 790 outer / 1 064 inner | 1 790 outer / 1 064 inner | 2 048 front / 2 662 rear | 2 190 |
| **Total visual (budget 8-35 k)** | **21 838** | **24 280** | **31 188** | **26 350** | **17 472** | **20 674** |
| UCX hulls (verts) | 2 (12 / 10) | 3 (8 / 10 / 8) | 4 (12 / 8 / 8 / 8) | 3 (12 / 8 / 8) | 5 (10 / 8 / 12 / 30 / 30) | 3 (12 / 10 / 8) |
| `traffic_validate` | OK | OK | OK | OK | OK | OK |

All parts: transforms applied, no modifiers, no loose geometry, no non-manifold edges, outward normals, `UVMap` present, non-overlapping
(0.00 % overlap measured at 384 px) and inside 0..1; Body origin = vehicle origin, wheel pivots at the axle centre (right wheels are
mirror-built, no negative scales). Remaining open boundary edges on the Body (96-230) are by design: window reveals, lamp lens patches and the
rust decal patches of the pickup lie as thin open sheets on the skin. The validator now also warns when a ROOT `wheel_width_*` differs from the
measured tyre width, and errors on a collision hull thinner than 0.15 m.

### Reported heights (read this before using `dimensions.height`)
* **Van**: `dimensions.height` 2.46 m includes the roof rack; the cargo roof is **2.30 m** (ROOT `height_roof`, JSON `height_roof`).
* **Pickup**: `dimensions.height` 2.05 m is the top of the headache rack; the cab roof is **1.62 m** (ROOT / JSON `height_cab_roof`).
* **Tractor**: 2.86 m is the tip of the cab-roof antenna; the roof panel is about 2.67 m, the beacon about 2.80 m.
* **Lorry / coach**: `width_with_mirrors` (3.09 / 3.13 m) is 0.3 m wider than the body on each side (mirror arms were shortened in the round-2 fix).

## 3. Materials (contract names; UE master-material instances by name)
* **Body** (<= 8 slots on all six): Compact / Van / Lorry / Coach `M_Paint M_Paint2 M_TrimBlack M_TrimGrey M_Headlight M_Taillight M_Indicator M_Plate`;
  Tractor `M_Paint M_Paint2 M_TrimBlack M_TrimGrey M_Rubber M_Headlight M_Indicator`; Pickup `M_Paint M_Chrome M_TrimBlack M_Headlight M_Taillight M_Indicator M_Plate M_Traffic_Rust`.
* **Glass**: `M_Glass` only (the only translucent part). **Interior**: `M_TrimBlack M_IntDash M_IntSeat M_IntTrim` (pickup without `M_IntTrim`), dark cheap cabin + driver silhouette.
* **Wheels**: `M_Tyre M_Rim M_RimDark M_Chrome` (+ `M_TrimGrey` van, `M_Paint2` tractor rims). Inner wheels of dual pairs only `M_Tyre M_Rim`.
* **Traffic-specific**: `M_Traffic_Rust` (pickup: rust patches, lower sills, bed interior **and the bed floor planks** - the former `M_Traffic_Wood` slot was folded
  into it so the Body keeps 8 slots; give the UE instance a weathered rust / dirty-wood look). `M_Traffic_Wood` still exists in the file for future assets.
* `M_Paint` = body paint (3 recommended variants per vehicle in the JSON `paint_variants`, linear + sRGB), `M_Paint2` = accent (window band / bumpers / rims).

## 4. Wheels, axles, driven / steered flags (JSON `wheels` and `axles`)
* 4-wheelers use keys `FL FR RL RR` (JSON also has `wheel_map`); lorry and coach use keys `1..n` in build order (front pair first, then outer / inner wheel of each rear side) - do not infer the side
  from the key, read `side` and `center` of each entry. **There is no `wheel_map` for the 6-wheel coach and the 10-wheel lorry; use the `wheels` list and the `axles` list.**
* Every wheel entry: `center [x,y,z]`, `radius`, `width`, `axle` (0 = front), `side` (`L`/`R`), `steering`, `driven`, `dual_with` (name of the twin; drive both from one
  physics wheel), `file`.
* Lorry: 3 axles - axle 0 steered, axle 1 (wheels 3-6) **driven**, axle 2 (wheels 7-10) undriven tag axle (6x2). Coach: axle 0 steered, axle 1 (wheels 3-6) driven.
  Tractor: all four driven (4WD), front pair steered. Compact / Van FWD, Pickup RWD.

## 5. Anchors (car-space metres; empties are not exported, the JSON has them)
`lights.head_l/head_r/tail_l/tail_r/reverse` (all six, the round-1 export of the coach and tractor had these keys corrupted; fixed: the regex now uses
`\g<1>_\g<2>`), `cameras.cockpit` / `cameras.bumper`, `exhaust` list.

| Anchor | Compact | Van | Lorry | Coach | Tractor | Pickup |
|---|---|---|---|---|---|---|
| Head L | 1.84, 0.50, 0.65 | 2.45, 0.60, 0.82 | 3.80, 0.90, 1.18 | 5.70, 0.92, 0.95 | 1.96, 0.31, 1.20 | 2.46, 0.70, 0.80 |
| Tail L | -1.84, 0.60, 0.74 | -2.72, 0.78, 1.16 | -4.49, 1.06, 1.58 | -6.00, 1.06, 1.20 | -1.60, 0.42, 2.69 | -2.40, 0.90, 1.15 |
| Reverse | -1.84, 0.0, 0.62 | -2.72, 0.0, 0.88 | -4.49, 0.70, 1.31 | -6.00, 0.70, 0.80 | -1.60, 0.0, 2.69 | -2.40, 0.62, 0.62 |
| Cockpit cam | 0.40, 0.36, 1.18 | 0.62, 0.46, 1.62 | 2.80, 0.52, 2.15 | 5.00, 0.62, 2.20 | -0.80, 0.0, 2.10 | -0.02, 0.40, 1.40 |
| Bumper cam | 1.90, 0.0, 0.45 | 2.58, 0.0, 0.55 | 3.92, 0.0, 0.65 | 5.90, 0.0, 0.70 | 2.00, 0.0, 0.75 | 2.52, 0.0, 0.50 |
| Exhaust | -1.94, 0.45, 0.30 | -2.88, 0.55, 0.36 | 1.50, -1.18, 3.52 (stack) | -6.05, -0.75, 0.48 | 0.40, -0.30, 2.46 (stack) | -2.44, 0.30, 0.46 |

## 6. Collision (UCX hulls, all convex, <= 32 verts, none thinner than 0.15 m)
Wheels get no collision (vehicle physics). Hulls: Compact 2 (front half / cabin + tail), Van 3 (cargo / cab / nose), Lorry 4 (cab, box, chassis rails, tandem underside),
Coach 3 (nose wedge 0.95 m deep, passenger deck, tail wedge 0.9 m deep - the round-1 0.03 m plate was replaced), Tractor **5** (bonnet, cab, chassis + hitch,
**plus one fender + big rear tyre hull per side**, so other cars cannot drive into the 1.2 m wide rear fenders), Pickup 3 (bonnet, cab, bed).
Traffic scale range for variety: 0.96-1.04 (compact) / 0.97-1.03 (others).

## 7. Round-2 fix log (art-director findings)
* **Coach / tractor blockers**: stale exports and missing UVs fixed by rebuilding the geometry from the scripts, running `uv_a`, `uv_b`, `uv_wheels`, `validate` (OK, UV overlap 0.00 %)
  and `export`; FBX, JSON, ROOT properties and live meshes agree again (tractor height 2.8606, coach wheel tris 1790 / 1064 ...). Corrupt `lights` keys fixed, all five keys present.
* **Coach**: tail hull rebuilt as a 0.9 m deep wedge; mirrors pulled in to about 0.3 m beyond the body with slim tall heads and a second lower arm; destination board with bevelled housing and amber display.
* **Tractor**: two rear fender/tyre hulls added (5 hulls).
* **Lorry**: mirrors pulled in (3.56 m -> 3.09 m overall) and slimmed; drivetrain made consistent: **6x2, only axle 1 driven**; JSON documents the wheel layout; total 31 188 tris (headroom 3.8 k).
* **Compact**: ROOT wheel width synced (0.183); domed headlamp lenses over a chrome reflector bowl and domed tail lenses; roof / bonnet rows smoothed with 5 Laplacian passes; wheels 28 / 24 segments (2 058 tris instead of 2 330).
* **Van / pickup**: ROOT wheel widths synced, degenerate boolean slivers removed by `heal_degenerate()` (0 warnings), pickup Body reduced from 9 to 8 material slots, rack heights documented (above).
* **Library**: `sync_wheel_root_props()` (every vehicle writes the measured tyre width to the ROOT), `heal_degenerate()`, `lamp_unit_domed()` / `lens_pair(bulge=...)`, validator checks for hull thickness and ROOT wheel width.

## 8. Known imperfections
* The compact still has a blunt, low fascia (bumper bands are part of the body shell, not separate meshes); the van nose is short and snub (intentional cab-forward van shape).
* Interiors are dark, cheap blocks with a driver silhouette (cockpit camera only; the coach seats are simple cushion + back boxes).
* Decal patches (rust, lamp lenses) are open single-sided sheets 3 mm above / below the skin; they are not welded (by design).
* Lorry mud flaps / ladder / underrun bar are thin boxes; the 6x2 tag axle has no steering or lift logic (static).
* Tractor rear lugs sink 3 mm under the ground plane at rest (wheel bbox radius 0.8035 vs axle height 0.8000).
