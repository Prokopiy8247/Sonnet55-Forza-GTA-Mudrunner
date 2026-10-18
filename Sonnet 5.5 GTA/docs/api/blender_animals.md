# Blender animals (lane 12) - `res://gta/generated/models/animals/<id>.glb`

18 low-poly, faceted, **skeleton-free** animals authored in Blender (`GTA_GODOT/Animals` in `GodotSonnet5.5GTA.blend`), exported with `gta_lib.export_glb`.
Articulated parts are separate meshes whose node origin is the joint, so Godot animates them by rotating nodes (procedural gaits, no AnimationPlayer needed).
Rebuild everything: `tools/blender/animals_build_all.py` (set `ONLY=[ids]` first for a subset); shared helpers in `tools/blender/animals_lib.py`;
builders `animals_deer.py`, `animals_canines.py`, `animals_small.py` (cat, rabbit), `animals_birds.py`, `animals_farm.py` (boar, cow, horse), `animals_sea.py`.
All scripts are idempotent (`clear_asset("<id>__")` first). Workshop slots `workshop(12, i, 8)`.

## Contract (probe-verified in Godot)
* Metres, real-world-ish scale, **forward = -Z in Godot** (+Y in Blender), up = +Y. `_R` = animal's right = **+X**, `_L` = **-X** (same as the character spec).
* **Origin**: land animals and birds = on the ground under the body middle (soles at y = 0, never below). Water animals (fish, shark, dolphin, sea turtle) = body centre (y = 0 is the body centre line; nothing is "on the ground").
* Node names are exact (no `<id>__` prefix). All parts are `MeshInstance3D`. Positions below are in **model space, rest pose**, Godot axes `(x, y up, z)`; the `position` of a *nested* node is relative to its parent (e.g. deer `Head` has `position = (0, 0.42, -0.42)` under `Neck`). Rest pose has identity rotation on every node, so a pure rotation of a node pivots exactly at the listed point.
* Hierarchy: `Head` is a child of `Neck` only for deer and horse; `Ear_L/R`, `Jaw`, `Antlers` are children of `Head` (they follow head turns/nods). Everything else is a direct child of the GLB root. Use `find_child(name, true, false)`.
* Materials (names are exactly these in every GLB, **but the colours differ per species** - each GLB has its own copy): `AnimalFur` (main coat, tint this for variants), `AnimalBelly` (underside / light markings), `AnimalDark` (extremities, ears, muzzle, patches, fin edges), `Hoof`, `Antler` (antlers, horns, tusks, shark teeth), `Beak`, `Accent` (species detail: nose, udder, beak/legs of birds, fish fins), `Eye` (shared near-black), `AnimalShell` (turtle). No textures, flat shaded. Do **not** replace these by name globally - that would erase the per-species look; override per surface with `Util.replace_material` only on the GLB you tint.
* No collision, no LOD, no UVs/textures (colours only). Tri counts are the real Godot counts (probe).

## Animation cheat sheet (Godot axes)
* **Leg swing = rotation about local X.** `rotation.x = +a` swings the foot **forward** (toward -Z), `-a` backward. Walk/trot are diagonal pairs: `Leg_FL` + `Leg_BR` in phase, `Leg_FR` + `Leg_BL` at +0.5 cycle. Amplitude A (rad): walk 0.30, trot 0.45, gallop/flee 0.65. Phase speed that avoids foot sliding: `omega = TAU * v / (4 * L * sin(A))` with `L` = hip height from the table, `v` = ground speed. A small bob (`Body`/all nodes y +- 0.01*L) sells it. Rabbit: hop = both front legs together, both hind legs together (`A` 0.7), body pitch +-10 deg.
* **Head pitch** = rotation about X on `Head` (positive = nose up; deer/horse grazing: `Neck.rotation.x = -0.6` then `Head.rotation.x = -0.2`). Head yaw = rotation about Y. Tail wag = rotation about Y (+-0.4), tail raise = about X. Ear flick = about Z / X (+-0.3).
* **Jaw** (dog, coyote): closed at rest, `Jaw.rotation.x = -0.35` opens (front drops). **Shark `Jaw`: rest pose is already ~13 deg open (menacing)**; `rotation.x = +0.23` closes it, `-0.3` opens wide (bite).
* **Birds**: flapping = rotation about **Z** (the forward axis): `Wing_R.rotation.z = +a`, `Wing_L.rotation.z = -a` (a = -0.5 .. +0.7 rad, up-stroke positive; wings are modelled spread with 8 deg dihedral). `Leg_L/R` swing about X for walking (A 0.5, short fast steps), tuck legs in flight by `rotation.x = -1.0` (or hide them). `Head` bob/peck: rotation about X on `Head`. **Variants:** `seagull` / `bird_small` = wings spread (flying/gliding); `seagull_perched` / `bird_small_perched` = wings folded along the flanks (standing/walking/pecking). Same node names and pivots in both; swap the GLB when taking off / landing.
* **Fish / shark / dolphin swim**: wiggle `Fin_Tail` about **Y** (`+-0.35` rad at ~2-3 Hz; shark slower, 1 Hz, +-0.25) and optionally yaw the whole root with the same sine (phase-lagged) for a body wave. **Dolphin flukes are horizontal**: wiggle `Fin_Tail` about **X** instead (`+-0.30`). Pectoral `Fin_L/R`: roll about Z/Y by +-0.25 (fish) for hovering/steering; keep still when gliding. `Fin_Dorsal` is static (the pivot is its base if you want to tilt it).
* **Sea turtle**: `Flipper_FL/FR` row about the local Z axis (+-0.5 rad, mirrored: right = +a, left = -a, ~0.6 Hz), hind flippers +-0.25, `Head` nods about X.

## Assets
Sizes are the Godot AABB (width x, height y, length z) in metres. `L` = hip/shoulder pivot height above the ground (leg length for the swing formula).

| id | size (w x h x l) | tris | reference size | nodes (hierarchy: `>` = child of previous) | notes |
|---|---|---|---|---|---|
| deer | 0.54 x 1.89 x 2.36 | 430 | 1.42 m at the withers | Body, Neck > Head > (Ear_L, Ear_R), Leg_FL/FR/BL/BR, Tail | doe, white rump patch + tail underside |
| deer_buck | 0.68 x 2.48 x 2.36 | 514 | same body | as deer + `Antlers` (child of Head) | 5-point antlers as ONE separate mesh, origin at the skull top; hide it to get the doe look |
| dog | 0.32 x 0.91 x 1.38 | 416 | 0.63 m shoulder | Body, Head > (Ear_L, Ear_R, Jaw), Leg_*, Tail | German-shepherd colours: tan, black saddle/muzzle/ears |
| coyote | 0.28 x 0.85 x 1.49 | 432 | 0.61 m shoulder | same as dog | leaner than the dog, head carried low, broad tan ears with dark tips, long snout, dark-tipped bushy hanging tail, Jaw for the bite |
| cat | 0.20 x 0.45 x 0.70 | 334 | 0.27 m shoulder | Body, Head > (Ear_L, Ear_R), Leg_*, Tail | orange tabby, ringed raised tail (tail tip 0.45 m high) |
| rabbit | 0.24 x 0.42 x 0.56 | 304 | 0.26 m back, ears to 0.42 | Body, Head > (Ear_L, Ear_R), Leg_*, Tail | crouched hop stance, cotton-ball `Tail` |
| seagull | 0.91 x 0.25 x 0.45 | 250 | 0.45 m long, 0.9 m span | Body, Head, Wing_L, Wing_R, Leg_L, Leg_R, Tail | wings spread, black tips |
| seagull_perched | 0.14 x 0.25 x 0.45 | 234 | same | same | wings folded |
| bird_small | 0.46 x 0.13 x 0.22 | 250 | 0.22 m long (crow-like dark bird) | same as seagull | wings spread |
| bird_small_perched | 0.07 x 0.13 x 0.22 | 234 | same | same | wings folded |
| boar | 0.48 x 0.74 x 1.67 | 348 | 0.72 m shoulder | Body, Head > (Ear_L, Ear_R), Leg_*, Tail | two `Antler` tusks live in the Head mesh; dark bristle ridge |
| cow | 0.74 x 1.51 x 2.67 | 458 | 1.40 m withers | Body, Head > (Ear_L, Ear_R), Leg_*, Tail | black/white patches, horns (in Head), udder (in Body), tufted tail |
| horse | 0.54 x 1.93 x 2.22 | 428 | 2.2 m long, ~1.4 m withers (built at 0.85) | Body, Neck > Head > (Ear_L, Ear_R), Leg_*, Tail | chestnut, dark mane (in Neck) and tail |
| fish_a | 0.17 x 0.16 x 0.30 | 194 | 0.30 m | Body, Fin_Tail, Fin_Dorsal, Fin_L, Fin_R | orange clown-style reef fish with white bands |
| fish_b | 0.27 x 0.23 x 0.50 | 158 | 0.50 m | same | silver, blue-grey back, forked tail |
| shark | 1.56 x 1.38 x 3.20 | 294 | 3.2 m | Body, Fin_Tail, Fin_Dorsal, Fin_L, Fin_R, Jaw | grey / white belly, teeth rows (Body = upper, Jaw = lower), tall dorsal, long upper tail lobe |
| dolphin | 0.90 x 0.77 x 2.00 | 210 | 2.0 m | Body, Fin_Tail (horizontal flukes), Fin_Dorsal, Fin_L, Fin_R | optional asset, done |
| sea_turtle | 1.25 x 0.28 x 0.86 | 194 | 0.86 m head-to-tail (shell 0.6 m, flipper span 1.25 m) | Body, Head, Flipper_FL/FR/BL/BR, Tail | optional asset, done; scute-patterned shell (`AnimalShell` + `AnimalDark`) |

### Joint pivots (model space, Godot axes `(x, y, z)`; nested nodes are relative to the parent in the scene tree)
* **deer / deer_buck**: Leg_FR `(0.15, 1.14, -0.46)`, Leg_BR `(0.15, 1.12, 0.60)` (L 1.14 / 1.12), Neck `(0, 1.30, -0.60)`, Head `(0, 1.72, -1.02)`, Ear_R `(0.06, 1.80, -0.99)`, Antlers `(0, 1.80, -0.97)`, Tail `(0, 1.27, 0.77)`.
* **dog**: Leg_FR `(0.09, 0.50, -0.27)`, Leg_BR `(0.09, 0.47, 0.27)` (L 0.50 / 0.47), Head (neck base) `(0, 0.52, -0.34)`, Jaw `(0, 0.62, -0.51)`, Ear_R `(0.05, 0.73, -0.49)`, Tail `(0, 0.50, 0.37)`.
* **coyote**: Leg_FR `(0.08, 0.50, -0.29)`, Leg_BR `(0.08, 0.46, 0.29)` (L 0.50 / 0.46), Head `(0, 0.52, -0.36)`, Jaw `(0, 0.595, -0.55)`, Ear_R `(0.05, 0.70, -0.525)`, Tail `(0, 0.49, 0.41)`.
* **cat**: Leg_FR `(0.05, 0.215, -0.125)`, Leg_BR `(0.054, 0.215, 0.125)` (L 0.215), Head `(0, 0.21, -0.16)`, Ear_R `(0.04, 0.34, -0.22)`, Tail `(0, 0.195, 0.185)`.
* **rabbit**: Leg_FR `(0.04, 0.135, -0.115)` (L 0.135), Leg_BR `(0.066, 0.185, 0.115)` (L 0.185), Head `(0, 0.15, -0.14)`, Ear_R `(0.03, 0.24, -0.18)`, Tail `(0, 0.15, 0.205)`.
* **boar**: Leg_FR `(0.14, 0.46, -0.31)`, Leg_BR `(0.15, 0.48, 0.37)` (L 0.46 / 0.48), Head `(0, 0.48, -0.46)`, Ear_R `(0.08, 0.66, -0.61)`, Tail `(0, 0.55, 0.53)`.
* **cow**: Leg_FR `(0.205, 1.02, -0.62)`, Leg_BR `(0.225, 1.06, 0.76)` (L 1.02 / 1.06), Head (neck base) `(0, 1.22, -0.82)`, Ear_R `(0.125, 1.29, -1.24)`, Tail `(0, 1.28, 0.97)`.
* **horse**: Leg_FR `(0.15, 1.12, -0.51)`, Leg_BR `(0.15, 1.11, 0.53)` (L 1.12 / 1.11), Neck `(0, 1.25, -0.56)`, Head `(0, 1.70, -0.94)`, Ear_R `(0.05, 1.78, -0.89)`, Tail `(0, 1.21, 0.68)`.
* **seagull(+perched)**: Wing_R `(0.04, 0.162, -0.032)` (mirrored for L), Head (neck base) `(0, 0.173, -0.108)`, Leg_R `(0.025, 0.101, 0)` (hip, L 0.10), Tail `(0, 0.137, 0.122)`. **bird_small(+perched)**: Wing_R `(0.02, 0.081, -0.016)`, Head `(0, 0.086, -0.054)`, Leg_R `(0.013, 0.050, 0)`, Tail `(0, 0.068, 0.061)`.
* **fish_a**: Fin_Tail `(0, 0, 0.10)`, Fin_Dorsal `(0, 0.06, 0.01)`, Fin_R `(0.03, -0.01, -0.04)`. **fish_b**: Fin_Tail `(0, 0, 0.14)`, Fin_Dorsal `(0, 0.07, 0)`, Fin_R `(0.04, -0.01, -0.04)`.
* **shark**: Fin_Tail `(0, 0, 1.16)`, Fin_Dorsal `(0, 0.34, -0.14)`, Fin_R `(0.26, -0.19, -0.76)`, Jaw `(0, -0.19, -0.93)`. **dolphin**: Fin_Tail `(0, 0, 0.74)`, Fin_Dorsal `(0, 0.22, 0.05)`, Fin_R `(0.15, -0.14, -0.38)`.
* **sea_turtle**: Flipper_FR `(0.20, 0, -0.14)`, Flipper_BR `(0.13, 0, 0.24)`, Head `(0, 0.05, -0.24)`, Tail `(0, 0.03, 0.30)`.

### Suggested colliders / sizes for code
Land animals: a capsule along the body axis is enough - deer r 0.30, length 1.7, centre y 1.0; dog r 0.17, l 0.9, y 0.38; cat r 0.10, l 0.45, y 0.17; boar r 0.25, l 1.1, y 0.45; cow r 0.40, l 1.9, y 0.95; horse r 0.30, l 1.5, y 0.95; rabbit r 0.10, l 0.3, y 0.12. Hit zones by height: head = above the `Head` pivot. Water animals: capsule along Z through the origin (shark r 0.4, l 2.6; dolphin r 0.3, l 1.6).

## Known limits / gotchas
* Poses are baked: land animals stand in a neutral pose with the zig-zag hind legs modelled in; the leg meshes keep their bends when rotated (rigid swing, no knee flex). Fine at game distances, not for close-ups.
* Open (non-manifold) edges exist only where parts are intentionally hidden inside another part (leg tops inside the body, ear/neck roots, antler/tusk/tooth bases). No stray geometry otherwise.
* Eyes are tiny closed pyramids (`Eye` material, 6 tris each) pressed into the head: they read as dark insets, not eyeballs; no blink/eyelids.
* Shape quality honest note: deer, cow, shark, fish, cat, rabbit, seagull and the dog read cleanly in all views. The **horse is the weakest** (slim legs, small head, boxy barrel), the coyote is a lean cousin of the dog (reworked once: lower head, broad tan ears, thicker neck - good enough at game distance, close-ups show its hind legs as a rigid zig-zag), boar leans warthog-like. Improving them would only need number tweaks in `animals_canines.py` / `animals_farm.py`.
* `Eye` is the only non-per-species material; every other material datablock lives in the master as `<Role>__<species>` (e.g. `AnimalFur__deer`) and is renamed to `<Role>` only for the duration of the export (`animals_lib.export_animal`). Do not run `gta_lib.export_glb` directly on these roots or the GLB would contain the `__species` suffix.
* The two `*_perched` bird GLBs are separate files (not a pose of the flying one); wings do not fold by rotation alone.
