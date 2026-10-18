# Wildlife + underwater world (`Game.sys(&"wildlife")`, class `WildlifeSystem`)

Owner: Wildlife/underwater agent. Files (all `gta/code/systems/`): `wildlife_system.gd` (system, spawning, tick loop), `wildlife_defs.gd` (species + region tables, tunables),
`wildlife_regions.gd` (habitat classification, tree grid, pasture search, bird perches), `wildlife_world.gd` (per-tick context shared with the brains),
`animal.gd` (`Animal`, CharacterBody3D hit body), `animal_model.gd` (GLB -> Animal, coat tints, mesh merging), `animal_anim.gd` (procedural limbs),
`wildlife_brain.gd` (land + bird behaviour), `marine_brain.gd` (shark), `underwater_fish.gd` (fish MultiMesh schools), `underwater_world.gd` (wreck, coral, kelp, rocks, bubbles),
shader `gta/generated/shaders/underwater_sway.gdshader` (kelp sway). Tests: `gta/tests/wildlife_test.gd` (headless), `wildlife_shots.gd` (screenshots), `wildlife_probe.gd` / `wildlife_dbg.gd` (dev probes).

## STATUS (read first)
Everything below is WORKING = run in-game headless via `wildlife_test.gd` (all green, 26 checks) and, for the visuals, with the real renderer (`screenshots/wildlife/herd.png`, `wreck.png`, `shark.png`).
NOT done / limited: see "Not done". `tools\gd.ps1 check` = `VALIDATE OK`.

```
powershell -NoProfile -File tools\gd.ps1 exec -Script res://gta/tests/wildlife_test.gd -Seconds 140 -GameArgs "--no-traffic --no-peds"
powershell -NoProfile -File tools\gd.ps1 shot -Out screenshots\wildlife\herd.png -GameArgs "--exec=res://gta/tests/wildlife_shots.gd --scene=<herd|boar|gulls|fish|shark|wreck> --delay=5 --time=11 --no-peds --no-traffic"
```

## What it does
* **Region spawning** around the player: ring 42..118 m (hidden: out of the camera frustum), first fill / after a teleport > 90 m is instant (from 22 m) for ~2 s. `WildlifeRegions.classify(x, z)` returns
  `hills woods park beach harbour industrial residential pasture` (from `WorldLayout.nature_zones`, districts, piers); `WildlifeDefs.REGION_TABLE` holds per-region species weights, group sizes, per-species caps and a per-region target.
  Hills / woods / park: deer herds of 2-5 (+ a buck), boar, coyote, rabbits, crows. Beach / harbour: seagulls (perched on pier decks, bollards, benches, sand; others flying along the coast), harbour also dogs / cats / crows,
  industrial and residential: cats, dogs, crows. A tree-free flat **pasture** (found at boot, see log line `[Wildlife] pasture ...`) hosts cows (+ a horse); it is NOT fenced (no fence prop with known dimensions, cows stay inside by steering).
* **Caps / tiers**: <= 30 land + air animals (`WildlifeDefs.CAP_LAND`; sharks do not count), <= 40 fish. Near (< 58 m) = full limbs + obstacle rays + ground rays; mid (58..112 m) = movement at 20 Hz, decisions every 0.45 s, no limb animation;
  despawn > 150 m, or > 100 m and out of view; despawned animals go to a per-species pool (6 each). One loop ticks everything (no `_process` per animal). Measured headless: ~1 ms per physics tick with 54 animals (all animated near), well under the 1.5 ms budget for 30.
* **Behaviour** (data driven by `WildlifeDefs.SPECIES`): wander / graze (head down, nibble) / idle (look around) / walk with leg gait phase `omega = TAU*v/(4*L*sin(A))` (feet do not slide), tail wag (dog), white tail flag (deer), ear flicks, rabbit hop;
  flee from the player (notice radius scaled by speed / crouch / vehicle / aiming), fast vehicles, gunshots and explosions (`Events.gunshot / explosion`, delayed by distance); alert -> flee with a reaction delay; herd alarm + followers keep to the leader;
  wild species stay off roads, water, trees (look-ahead steering with terrain / water / slope / tree grid / forward ray). Wounded bold animals (boar, coyote, dog) can fight back: bite 13 / 6 / 5 damage (`GC.DMG_ANIMAL`, source = animal) with a short chase;
  they never attack unprovoked. Birds: perch / peck / walk, take off when approached (wings flap, legs tucked, banking), fly goal to goal biased to the coast, land on a free perch (model swap folded <-> spread).
* **Damage contract**: `Animal` is a `CharacterBody3D` on layer `GC.L_ANIMAL`, groups `animal` + `damageable`, `apply_damage(amount, info)` (head x2.2), `knockback`, `die`, `is_dead`, `faction = GC.F_ANIMAL`, `body_height`.
  Bullets / melee / explosions / run-overs (`VehicleBase._run_over_check` looks at `L_ANIMAL`) work; a hit by a vehicle flings the animal. Death = ragdoll-lite: land animals topple onto their side with stiff limbs (tumble while flung),
  birds drop, swimmers roll belly-up and float; corpses stay 38 s then sink + are pooled. It does NOT emit `Events.character_died` (that would play human death voices, loot drops and murder crimes); instead the system signals
  `animal_killed(animal, killer)` and `animal_spawned(animal)`. Killing animals is not a crime.
* **Marine**: fish schools (`UnderwaterFish`, 2 MultiMeshes, merged fish_a / fish_b GLBs, 6-12 per school, boids-light: a drifting centre + per-fish offsets with body wiggle; schools sit at pier tips / the wreck / random shelf spots, scatter from a swimming player and from boats).
  **Shark** (`MarineBrain`, max 2, spawned in deep water 55-130 m from the player when the player is in/near the sea): patrols with the dorsal fin near the surface, notices a swimmer (<= 40 m) or boat (<= 55 m), circles for 5-9 s,
  charges and bites (22 dmg +-, 2.2 s cooldown, up to 3 bites, camera shake, `Events.notification("Shark!")`, splash sound), then retreats and loses interest. **Only swimmers in deep water are attacked**: seabed below -5 m, z >= 200, > 11 m from any pier
  (`MarineBrain.attackable_pos`); sharks never swim over a seabed shallower than -3.6 m. Shooting it makes it retreat; it has 220 HP and dies belly-up. Boats are circled but never damaged. `Game.cheats["sharks"] = false` disables attacks.
* **Underwater world** (`UnderwaterWorld`): `props/shipwreck` placed at `diving_wreck`, tilted onto the slope, trimesh collider (layer `L_WORLD`, surface `metal`) so a diver can swim around it, 3 cash pickups (600/750/900) spawned on the hull through `CombatSystem.spawn_pickup`;
  anchor + 2 sunken crates beside it; MultiMesh scatter over the near-shore shelf (x +-285, z 176..300, depth 1.8+ m, slope < 26 deg, clear of piers): ~70 coral (coral_a/b/c), ~94 kelp (kelp_a/b with the `underwater_sway` vertex-bend shader), 36 sea rocks, 14 urchins.
  Diver bubbles (CPUParticles3D following the head while `head_underwater`): exhale puffs every 7 s, a steady scuba stream (every 4 s pulses) with `has_scuba` / `Game.cheats["scuba"]`. Fog / colour / audio muffling are the Environment + Audio agents' automatic treatment (untouched).
* **Cheat**: `Game.cheats["wildlife"] = false` despawns everything (animals, fish, hides the seabed props) within a frame and stops spawning; setting it back on refills within ~3 s.

## Public API (`WildlifeSystem`)
`get_animals()`, `active_count()` (living land + air), `count_species(sp)`, `spawn_animal(sp, pos, opts)` (`yaw variant flying herd`), `spawn_group(sp, center, n, {buck})`, `spawn_shark(pos)`,
`release(a)`, `despawn_all()` / `reset()` (SaveSystem calls it on load), `set_enabled(on)`, `auto_population` (false for tests / cutscenes), `instant_fill` (seconds of unrestricted spawning), `stats` (spawned, despawned, killed, tick_us, land, birds, sharks, fish),
`fish` (`UnderwaterFish`: `add_school(xz, n, kind)`, `school_count()`, `clear()`), `uw` (`UnderwaterWorld`: `stats`, `wreck`, `wreck_body`, `place_treasure()`). Signals `animal_spawned`, `animal_killed`.
Save: `serialize()` returns `{}` (wildlife is not persisted); `deserialize()` clears and refills.
Species ids: `deer deer_buck boar coyote rabbit cat dog cow horse crow seagull shark dolphin sea_turtle` (dolphin / sea_turtle rows exist in the table but nothing spawns them yet).

## Tunables
`WildlifeDefs`: `CAP_LAND 30`, `CAP_FISH 40`, `RING_MIN 42`, `RING_MAX 118`, `NEAR 58`, `MID 112`, `DESPAWN_FAR 150`, `DESPAWN_HIDDEN 100`, `BODY_LIFETIME 38`, species rows (speeds, gait amplitudes, flee radius, health, bite), `REGION_TABLE`.
`MarineBrain`: `DEEP_Y -5`, `KEEP_Y -3.6`, `PIER_SAFE 11`, `NOTICE_SWIM 40`, `NOTICE_BOAT 55`, `BITE_DAMAGE 22`, `BITE_RANGE 2.3`.

## Not done / honest limits
* **Dolphins and sea turtles are NOT spawned** (GLBs and anim code exist: `AnimalAnim._swim`, species rows) - no brain yet. No light shafts, no plankton particles, no sand-ripple shader.
* No predator hunting (coyote does not chase rabbits), no day / night schedules beyond fewer gulls / crows at night, no sound ids of its own: only `gull`, `bird`, `splash`, `splash_big` exist in the audio bank
  (dog bark / cow moo / dolphin ids are guarded by `Sfx.has_sound` and stay silent). `files wildlife_audio.gd` (a synthesised-creature-sound helper) and `marine_fish.gd` + `marine_fish.gdshader`, `marine_shaft.gdshader`, `marine_sway.gdshader`
  appeared in this folder from ANOTHER writer during this session - they are not wired into `WildlifeSystem` (this module uses `UnderwaterFish`, `underwater_sway.gdshader`); the lead should decide which set to keep.
* Pasture is not fenced. Animals have no collision with each other or the player (kinematic hit bodies on `L_ANIMAL` only; the player's move mask ignores them). Leg poses are rigid swings (no knee flex), as documented in `blender_animals.md`.
* Animal-vs-vehicle: run-over damage comes from the vehicle code; animals also flee from fast vehicles within 24 m ahead of them.
* The shark's dorsal fin is only slightly above / at the surface in the afternoon sun (looks pale blue under water); real-renderer shot `shark.png` reads well.
* Perf numbers are headless CPU only; the real-renderer GPU cost of ~30 animals + 40 fish + ~215 MultiMesh seabed props was not profiled.
