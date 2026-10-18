# Blender lane 14 - underwater wreck + sea life, helipad, vending machine, ATM

Authored in Blender through MCP, exported with `gta_lib.export_glb`. Idempotent builders live in `tools/blender/lane14_*.py`
(`lane14_lib.py` = helpers + materials (copy of the lane 13 geometry helpers + organic helpers `blob`, `limb`, `ribbon`), `lane14_shipwreck.py`, `lane14_coral.py`, `lane14_kelp_rocks.py`,
`lane14_sea_props.py`, `lane14_street.py`; every script runs after `gta_lib.py` + `lane14_lib.py`, optional `ONLY=[ids]` selects a subset). Objects stay in the master `.blend`
under `GTA_GODOT/Nature` (underwater set) and `GTA_GODOT/StreetProps`; workshop row `workshop(14, slot, spacing)` (y = 2280).
All GLBs: `res://gta/generated/models/props/<id>.glb` (the brief overrides ARCHITECTURE s7 `nature/` for the underwater set), metres, flat shaded, colours only (named materials),
front = Blender +Y = **-Z in Godot**, `<assetid>__` prefix stripped, root children are the top level nodes. Glass-like / thin shells are single quads (materials import double sided).
Underwater materials are slightly desaturated / teal-tinted on purpose (the game's underwater fog + overlay sits on top). Triangle counts are Godot-probe values.

## Status

| id | status | tris (Godot) | budget | size X x Y(up) x Z m |
|---|---|---|---|---|
| `shipwreck` | DONE | 1927 | 2500 | 18.0 x 9.2 x 30.6 |
| `coral_a` branching | DONE | 364 | 400 | 1.25 x 1.66 x 1.61 |
| `coral_b` brain / dome | DONE | 362 | 400 | 2.19 x 0.76 x 1.57 |
| `coral_c` fans + tubes | DONE | 302 | 400 | 1.89 x 1.08 x 1.63 |
| `kelp_a` | DONE | 309 | 400 | 1.22 x 3.12 x 1.09 |
| `kelp_b` | DONE | 119 | 400 | 0.58 x 0.85 x 0.62 |
| `sea_rock_a` | DONE | 201 | 400 | 2.32 x 1.14 x 1.86 |
| `sea_rock_b` | DONE | 192 | 400 | 3.20 x 1.16 x 2.05 |
| `anchor` | DONE | 326 | 400 | 1.73 x 1.43 x 2.48 (lying on the sea bed, shank ~2.0 m) |
| `sunken_crates` | DONE | 204 | 400 | 2.61 x 1.29 x 1.99 |
| `clam_shell` | DONE | 328 | 400 | 0.94 x 0.81 x 0.73 |
| `starfish` | DONE | 85 | 400 | 0.36 x 0.10 x 0.34 |
| `sea_urchin` | DONE | 185 | 400 | 0.47 x 0.36 x 0.49 |
| `bubble_vent` | DONE | 209 | 400 | 1.77 x 1.27 x 1.57 |
| `helipad_pad` | DONE | 158 | 400 | 10.0 x 0.25 x 10.0 |
| `vending_machine` | DONE | 220 | 400 | 0.90 x 1.90 x 0.85 |
| `atm_machine` | DONE | 108 | 400 | 0.70 x 1.60 x 0.67 |
| `hospital_sliding_door_pair`, `police_door_pair` | NOT BUILT (optional, dropped - wrap-up order) | - | - | - |

Origins / forward for every underwater model: footprint centre on the sea bed (y = 0 is the sand; models sit exactly on it, the wreck 0.2 m into it), front +Y Blender = -Z Godot (round things have no preferred front).
Nothing has collision baked; use trimesh / a capsule at placement time (wreck: trimesh of `Body` or a few boxes; corals/rocks: a box/sphere if you want to block the player).

## 1. `shipwreck` (hero wreck, props/shipwreck.glb)

* 28 m coastal freighter, **heeled 38 deg onto its starboard bilge** (port side up, deck faces -X Godot), bow towards **-Z**, stern/propeller at +Z. Torn port plating with exposed ribs and curled plates, collapsed gunwale, cargo hold with slid crates + barrels,
  deckhouse with doorways + window holes (explorable from outside, one door leaf hangs open), wheelhouse with a broken roof flap + console + helm, funnel stump, snapped foremast with yard + rigging, boom swung over the port side, rail runs, windlass,
  open engine room (engine block, boiler, shaft, propeller, rudder), barnacle cones (`WreckBarnLt`), rust / algae colour bands, silt drifts against the buried side, debris on the sea floor (crates, barrel, loose hull plates, fallen spar).
* Size 18.0 (X) x 9.2 (height) x 30.6 (Z) m; Z extent -14.7 (bow) .. +15.9 (propeller). Origin = footprint centre at sea-bed level; lowest point 0.2 m BELOW the origin. Highest point (radar mast) 9.0 m.
  Place the node at the dive site's sea-floor height (`diving_wreck` is at (-22, -13.6, 268), seabed ~14 m deep -> wreck top at about -4.6 m).
* Nodes: `Body` (single mesh, 19 surfaces) + empties (Godot positions relative to the node): `DiverEntry (-4.26, 7.47, -2.4)` open water beside the breach (spawn / "dive here" marker),
  `TreasureSpot_1 (-1.58, 2.14, -3.9)` cargo hold among the crates, `TreasureSpot_2 (-0.43, 4.09, 8.2)` captain's cabin by the strongbox, `TreasureSpot_3 (-0.71, 1.14, 13.2)` engine room aft.
* Materials: `WreckRust WreckRustDk WreckRedLead WreckTeal WreckTealDk WreckWhite WreckBarn WreckBarnLt WreckAlgae WreckDeck WreckDeckDk WreckSteel WreckBrass WreckCrate WreckCrateDk RopeOld BarrelRed BarrelBand UWSilt`.

## 2. Sea life and set dressing (props/<id>.glb)

* `coral_a`: 5-limb branching coral (pink -> orange tips) on a grey-teal base rock. `coral_b`: layered brain/dome coral in purple with a pink and an orange satellite dome. `coral_c`: three lattice fans (orange / pink / purple) + 6 yellow / teal tube sponges on a rock.
  Pastel `Coral*` materials (`CoralPink CoralPinkDk CoralOrange CoralOrangeLt CoralPurple CoralPurpleDk CoralYellow CoralTeal`). Mix rotation (random yaw) and scale 0.7-1.6 when scattering.
* `kelp_a`: 9 ribbon strands up to 3.0 m + holdfast. Two nodes: `Body` (holdfast rocks + roots) and **`Blades`** (all ribbons, origin = base centre at the sea bed, tips at y = 3.0): sway it with a vertex shader keyed to local height, or rotate the node a few degrees about X/Z.
  `kelp_b`: short 0.85 m seaweed clump (15 blades). Materials `KelpDark KelpGreen KelpLight KelpOlive UWAlgae*`.
* `sea_rock_a` / `sea_rock_b`: algae-covered rocks (green `UWAlgae`/`UWAlgaeLt` tops, grey `UWRock` flanks, ribbon algae tufts); b has a tall standing stone + two lower humps (3.2 m wide).
* `anchor`: 1.8 m class admiralty anchor lying on the bed (crown + one fluke dug in, stock and shank raised, ring end 1.4 m up) with a short chain trailing along +Y. `AnchorIron`, `AnchorRust`.
* `sunken_crates`: pile of 4 crates (one tipped) + 1 barrel on a silt mound, algae mats on the tops, a loose plank.
* `clam_shell`: nodes `Body` (lower valve + pink mantle), `Lid` (upper valve; **origin = hinge at the back edge** (Godot (0, 0.27, +0.34)); modelled open ~55 deg - rotate about local X to open/close), `Pearl` (0.17 m sphere, material `Pearl`, slightly emissive) and empty `PearlPoint` (pickup / interaction anchor at the pearl).
* `starfish`: 5-armed 0.36 m, orange with tubercle dots. `sea_urchin`: 0.47 m spiky purple urchin (body + spines, sits on its underside).
* `bubble_vent`: rock chimney (tall 1.15 m stack + 2 small stacks on a mound, rust-stained rims, dark mouths) + empty **`Vent`** at the tip of the main chimney, Godot (0, 1.25, 0) - emit the bubble particles from here.
  Materials `UWRock UWRockLt UWRockDk UrchinBody WreckRust`.

## 3. Street props

* `helipad_pad`: 10 x 10 m slab 0.15 m thick, **origin = centre of the TOP surface** (y = 0 is the pad surface, slab goes down to -0.15, lights stand 0.1 above). Dark `HeliPad` field, light `HeliCurb` border band, **yellow ring** (`HeliYellow`, r 3.45-3.85, geometry) + **white H** (`HeliWhite`, geometry),
  four yellow corner wedges, 8 perimeter light blocks in material **`LampGlow`** (4 corners + 4 mid-edges; toggle emission at night by name). Empties: `Light_1..4` (corners, y = 0.25 - put OmniLights there), `Centre` (landing point). Symmetric: no front.
* `vending_machine`: 0.9 (W) x 1.9 (H) x 0.85 (D, incl. 0.05 proud trim), front +Y Blender = -Z Godot. Red cabinet, backlit product window in **`NeonCyan`** (cans / snack rows), magenta `Neon` header stripe under a `NeonCyan` light box, keypad + `NeonScreen` display, coin slot, `AtmGreen` bill-reader light, dispenser flap.
  Empty `UsePoint` (Godot (0, 0, -0.85), i.e. 0.85 m in front, on the ground) = where the player stands. Emissive parts to pulse by name: `NeonCyan`, `Neon`, `NeonScreen`, `AtmGreen`.
* `atm_machine`: free-standing kiosk 0.7 (W) x 1.6 (H) x 0.67 (D), front -Z Godot. Sloped head with a glowing **`NeonScreen`** (dark blue, emission 1.2 - same material name/values as the lane 9 interiors) in a light bezel, 4 `NeonCyan` soft-key bars, `NeonCyan` header strip, keypad shelf, card slot with `AtmGreen` ring, receipt slot, cash dispenser with a green glow lip, privacy side shields.
  Empty `UsePoint` = 0.85 m in front, on the ground. Mount it against a wall by placing it with its back (Godot +Z side) at the wall.

## 4. Scale check

Player 1.8 m: the vending machine (1.9 m) is a hair taller than the player, the ATM (1.6 m) reaches the chest/head, kelp_a (3.1 m) is ~1.7 characters tall, the anchor (shank ~2.0 m) is slightly taller than a player lying beside it, helipad 10 m (a heli_civil
fits; the 4.7 m sedan is less than half of it), the wreck is 28 m long / 9 m tall (about 6 sedans long).

## 5. Gotchas / known limits

1. The wreck is a hero-detail single mesh (1.9 k tris) - cull it by distance; no LOD baked.
2. Preview tip: Blender's "front" look camera shows the BACK (-Y side) of these +Y-facing props - use `back` or `[0.6, 1, 0.3]` to see the front.
3. Door pairs (`hospital_sliding_door_pair`, `police_door_pair`) were NOT built (dropped when the lead asked to wrap up) - the existing `props/elevator_door` / world doors remain the only sliding doors.
4. All emissive materials (`NeonCyan`, `Neon`, `NeonScreen`, `AtmGreen`, `LampGlow`, `Pearl`, `WreckTreasure` defined but unused) are plain Principled emission; Godot can scale them by name.
5. Materials introduced by lane 14 (plain colours): `Wreck*`, `UW*` (`UWSand UWSilt UWRock UWRockLt UWRockDk UWAlgae UWAlgaeDk UWAlgaeLt`), `Kelp*`, `Coral*`, `Clam*`, `Pearl`, `Star*`, `Urchin*`, `Anchor*`, `RopeOld`, `Barrel*`, `Heli*`, `Vend*`, `Atm*`, `DoorFrame*` (unused).
