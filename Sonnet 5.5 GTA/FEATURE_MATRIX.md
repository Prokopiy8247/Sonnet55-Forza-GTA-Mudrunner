# FEATURE MATRIX — Halcyon Bay

Statuses: `WORKING` (a functional in-game path was actually run), `PARTIAL`, `NOT IMPLEMENTED`. There are no missions by design.

**How "WORKING" was established:** the lead personally verified boot (21/21 systems, ~8 s headless), project validation (409 files, 0 failures) and several real-renderer screenshots. Per-feature behaviour was verified by the module agents with headless `exec` tests against the full booted game (148 test files in `gta/tests/`) and, for visuals, real-renderer screenshots. Audio was verified numerically only (nobody listened). Because the build was cut short on request to save usage, the last wave was NOT given a full end-to-end play-test or a performance pass — see Notes.

| Feature | Status | Notes |
|---|---|---|
| Stable Godot project / launches straight into free roam | WORKING | `tools\gd.ps1 check` = VALIDATE OK (409 files); Main boots 21/21 systems; no mission system exists |
| Third-person player (walk/run/sprint/jump/crouch) | WORKING | measured speeds, coyote jump, stamina, stairs/curb step-up |
| Camera (orbit, collision, aim, vehicle chase, shake) | WORKING | sphere-cast collision, shoulder swap, interpolation-safe |
| First-person toggle | PARTIAL | head-hidden FP view works; no arms/weapon viewmodel, no ADS cockpit view |
| Swimming and diving, lungs, drowning | WORKING | surface swim, dive, lung 20 s (longer with skill/scuba) |
| Cover system | WORKING | high/low cover, slide, corner wrap, vehicle cover, blind fire (15 tests); not used by civilians |
| Stealth mode and takedown | PARTIAL | crouch noise/visibility model + silent takedown tested on dummies; NPC/police perception does not read the values yet |
| Climb / vault / ladders | PARTIAL | vault, mantle and ladder climbing tested; no ledge hang or dodge/roll |
| Melee combat | PARTIAL | fists/knife/bat/crowbar swings, knockdown, takedown; no block, finisher or directional hit reactions |
| Ragdoll / death / respawn | WORKING | ragdoll cap 8, respawn at hospital, BUSTED respawn at police station |
| Compact 600x600 m world | WORKING | deterministic layout, builds in ~2 s, 43 named locations, backdrop and boundary |
| Districts (downtown, residential, industrial, waterfront, hills/park, airport, beach) | WORKING | all present and populated; 14 hero landmarks placed in wave 3 |
| Road network, markings, curbs, signals | WORKING | arterial, grid, loops, hill road, 36 signals, shader-drawn markings/wet look |
| Buildings (modular Blender kit + hero landmarks) | WORKING | kits + 14 hero GLBs; MultiMesh per sector; lit windows at night |
| Street props and nature | WORKING | 880+ furniture items, trees/palms/rocks; furniture validated against lane graph |
| Water (sea, beach, piers) | WORKING | stylised shader, swim volumes, piers, wreck site |
| Day/night cycle | WORKING | 24 min cycle, sky/sun/moon/stars, golden hour tuned |
| Street / vehicle / building lights | WORKING | pooled street-lamp lights, headlights, tail/brake, lit windows, neon |
| Weather (clear, cloudy, rain, fog, storm) | WORKING | rain particles, wetness, lightning; rain look checked in screenshots |
| Vehicle framework (enter/exit/drive) | WORKING | raycast-suspension RigidBody vehicles, seats, doors, camera |
| Cars (compact, sedan, sports, muscle, SUV, pickup, van, police cruiser) | WORKING | 8 distinct Blender cars, handling profiles, all spawn and drive in tests |
| Taxi / ambulance / fire truck / truck / tactical vehicle | WORKING | Blender models, drivable; taxi, ambulance, fire engine also have service behaviour |
| Motorcycle | WORKING | lean/wheelie, rider ejection on crash |
| Bicycle | WORKING | pedal-driven light bike |
| Boats | WORKING | speedboat buoyancy/planing/wake (15/15 tests); no sinking visuals beyond destruction |
| Helicopters | WORKING | civil + police, collective/cyclic/yaw, landing damage (50/50 tests) |
| Airplanes | WORKING | prop plane and jet take off within the runway, stall, crash (41/41 tests) |
| Carjacking | WORKING | pull driver out, driver reaction, crime events, police-car theft |
| Drive-by shooting | PARTIAL | seat API + aim path exist; not verified end to end in the game |
| Vehicle damage, smoke, fire, explosions | WORKING | collision damage, tyre/glass zones, fire at low health, explosion + wreck |
| Vehicle lights, horn, siren | WORKING | emissive swaps, flashing siren bars; sounds numerically verified only |
| Traffic (lane graph, signals, density, parked cars) | WORKING | 0 collisions / 0 red-light runs over 120 s sim; 45 parked-car slots |
| Pedestrians (sidewalks, crossings, reactions) | WORKING | ped graph walking, crossings obey signals, 60-ped cap, pooled |
| NPC panic / flee / fight / witnesses | WORKING | panic spread, hands-up, fight-back types, witness phone calls |
| Weapons: melee | WORKING | fists, knife, bat, crowbar |
| Weapons: handguns | WORKING | pistol, revolver |
| Weapons: SMG | WORKING | compact SMG |
| Weapons: shotguns | WORKING | pump, semi-auto |
| Weapons: rifles | WORKING | assault rifle, carbine, marksman |
| Weapons: sniper (scoped) | WORKING | scope overlay, ADS zoom |
| Weapons: grenade / rocket / grenade launcher | WORKING | projectiles, explosions with falloff and impulse |
| Weapon wheel | WORKING | slows time, radial selection |
| Weapon modifications | WORKING | suppressor, scope, grip, extended mag, flashlight, tint, bought at the bench |
| Ballistic material response | WORKING | sparks, dust, glass shards, decals; vehicle tyre/glass zones lightly tested |
| Wanted system 0-5 | WORKING | heat from crimes, witnesses, indirect reports, stars HUD |
| Police AI on foot and in vehicles | WORKING | combat brain, cover, PIT/boxing, SWAT/tactical vans |
| Pursuit / search / escape logic | WORKING | LOS-based pursuit vs search, escape timers per level, re-sighting |
| Roadblocks / helicopter support | WORKING | roadblocks ahead of the player, spike strips, police helicopter with searchlight (searchlight-cone fix not visually re-checked) |
| Busted / arrest and death / respawn | WORKING | arrest is probabilistic with live traffic/peds (one run of four stalled) |
| Gang / hostile NPCs | WORKING | 2-3 gang groups in industrial turf |
| Shops (weapons, ammo, armor, food) | WORKING | enterable interiors with clerks and menus |
| Clothing / barber / appearance | WORKING | wardrobe, clothes, hair, persisted |
| Safehouse (save, wardrobe, sleep, garage) | WORKING | apartment interior, sleep time-skip, 3-slot garage |
| Vehicle repair and customization garage | WORKING | paint, wheels, 19 Blender body parts, performance mods that change handling |
| Stored vehicles | WORKING | 6 slots, deliver by phone |
| Phone (taxi, quick save, photo mode, map) | WORKING | original smartphone UI; photo mode with filters |
| Economy (cash, pickups, drops) | WORKING | ~35 cash spots, health/armor/ammo/weapon crates, NPC drops |
| Store robbery | WORKING | aim at clerk, rob register, crime event |
| Taxi passenger service | WORKING | call, ride, pick destination, fare, skip (headless test; no screenshots) |
| Trains / transit | NOT IMPLEMENTED | viaduct, stations and train models exist but no train runs and platforms are unreachable |
| Parachute | WORKING | deploy, steer, flare, landing damage; procedural canopy (GLB canopy unused) |
| Underwater / scuba / lung capacity | WORKING | dive, lungs, scuba, shipwreck with cash, coral/kelp scatter |
| Wildlife | PARTIAL | deer, boar, coyote, rabbits, cats/dogs, seagulls, cows, fish schools, shark; no dolphins/turtles, few animal sounds |
| Ambulance / fire response | WORKING | dispatch to bodies/burning cars, paramedics and firefighters |
| Radio / in-vehicle media | PARTIAL | 4 procedural stations implemented; only numerically verified, never listened to |
| HUD (health, armor, ammo, wanted, money, speed) | WORKING | original design, verified in screenshots |
| Minimap | WORKING | rasterised map, blips, wanted area, indoor state |
| Full map screen / waypoint / GPS route | WORKING | pan/zoom, waypoint, route line |
| Pause / settings / status screen | WORKING | settings, controls, stats, skills |
| Character skills | WORKING | 7 use-based skills with real effects, persisted |
| Activities: shooting range | WORKING | scored rounds with real bullets (gold in bot test), cash + skill |
| Activities: stunt jumps | PARTIAL | jumps 1 and 2 driven successfully; jump 3 and bikes untested |
| Activities: races | PARTIAL | one 2-lap street race verified end to end; sea/air/off-road races, triathlon, golf, darts NOT IMPLEMENTED |
| Audio (procedural SFX, engines, sirens, ambience) | PARTIAL | fully original and synthesised; verified numerically, not by listening |
| Save / load | WORKING | JSON slots, atomic writes, round-trip tests |
| Admin / benchmark menu (F1) | WORKING | all spec bullets; 70/70 headless action tests |
| Blender-authored assets | WORKING | 291 GLBs from the live Blender session (vehicles, characters, weapons, buildings, props, animals, parts) |
| Gamepad support | NOT IMPLEMENTED | keyboard/mouse only |
| Tattoo shop, tow truck, hailing taxis from the street | NOT IMPLEMENTED | lowest-priority stretch items |
| Performance (pooling, LOD, tiered simulation) | PARTIAL | pooling/tiers/visibility ranges in place; per-car (~27 draw calls) and per-ped cost still high; no dedicated optimisation pass; vehicle LOD GLBs exist but are not loaded |
