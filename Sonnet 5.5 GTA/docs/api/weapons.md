# Weapons, combat, explosions, pickups and combat FX - API (Weapons agent)

Files: `gta/code/weapons/*` (WeaponDefs, WeaponMods, WeaponTrade, WeaponController, WeaponModel, Ballistics, Projectile, Explosion, CombatSystem),
`gta/code/combat/*` (MeleeResolver, CombatUtil, PickupBase + 5 pickup kinds), `gta/code/fx/*` (FxManager, FxRes).
Tests: `gta/tests/weapon_test.gd`, `weapon_explosion_test.gd`, `weapon_melee_test.gd`, `weapon_player_test.gd` (+ `weapon_test_kit.gd`, `weapon_shots.gd` visual QA).

## 1. Quick start for other modules

```gdscript
# a character gets a controller (the Player already does this)
var wc := WeaponController.new(); character.add_child(wc); wc.setup(character)   # sets character.weapons when it is null
wc.give_weapon(&"pistol", 60, true)        # id, total rounds, equip now  (new firearm: mag filled first, rest -> reserve)

# every frame (player: camera centre ray, AI: eye -> target)
wc.set_aim_ray(origin, direction)          # or AI: wc.aim_at_point(target_pos)  (uses character.ai_accuracy 0..1)
wc.set_aiming(true/false); wc.set_trigger(true/false)       # hold = automatic fire; edge = single shot for semi weapons
wc.fire_once()                             # AI: one shot / one swing, respects cooldown, returns true if it fired
wc.start_reload(); wc.melee_attack(heavy); wc.throw_grenade()
wc.equip(id) / equip_next() / equip_prev() / equip_slot(1..9) / holster()

# explosions / projectiles / pickups from anywhere
Game.sys(&"combat").explode(pos, radius, damage, source, {"weapon": &"x", "force": 9.0, "ignore": [self], "vehicle_mult": 6.0, "big": true})
CombatSystem.get_fx().impact(pos, normal, &"metal")        # pooled FX manager (null when combat is not booted)
Game.sys(&"combat").spawn_pickup(&"health", pos, 50, {"respawn": 90.0})
Game.sys(&"combat").spawn_weapon_pickup(&"smg", pos, 60, {"lifetime": 120.0})
Ballistics.shoot(space, from, dir, {...})                  # one bullet (mounted guns, scripted shots) - see section 5
```

## 2. WeaponController (child Node of a CharacterBase)

Stub contract kept (all members exist): `character, current_id, inventory, is_aiming, is_reloading`, signals `fired weapon_changed ammo_changed reloaded empty_clicked`,
`setup give_weapon has_weapon remove_weapon add_ammo refill_all_ammo get_weapon_ids equip equip_next equip_prev equip_slot holster set_trigger fire_once start_reload set_aiming melee_attack throw_grenade set_aim_ray aim_at_point get_current_def get_ammo_in_mag get_ammo_reserve can_fire_from_vehicle get_noise_radius serialize deserialize`.

Inventory entry: `inventory[id] = {"mag": int, "reserve": int, "mods": {mod_id: true}, "tint": Color}`. `fists` is always present. For `thrown` weapons (grenade) the mag holds 1 and the reserve the rest.

Additions (all additive):

| member | meaning |
|---|---|
| `give_weapon(id, ammo, equip_now := false)` | `ammo` = total rounds; owned weapon -> adds to reserve (capped) |
| `add_ammo(id, n) -> int` | rounds actually added (0 when full) |
| `get_ordered_ids()` | owned ids in wheel order (category, price) |
| `equip_slot(n)` | 1..8 = melee, handgun, smg, shotgun, rifle, sniper, heavy, thrown; pressing again cycles inside the category; 9 = fists |
| `begin_grenade_cook()` / `release_grenade()` | hold-to-cook grenade (fuse 3 s). `throw_grenade()` = quick throw. Works with any weapon equipped. Equipped grenade: trigger press cooks, release throws |
| `get_throw_preview() -> PackedVector3Array` | arc points for an aim preview |
| `toggle_flashlight()` | flashlight mod: manual toggle; also auto-on while aiming at night (`flashlight_auto`) |
| `toggle_fire_mode()` | carbine: burst <-> auto |
| `cycle_zoom()`, `hold_breath(bool)` | sniper: 4x / 8x, steady the sway for ~3.5 s |
| `set_mod(weapon_id, mod_id, on)`, `has_mod`, `set_tint(weapon_id, Color)` | customisation (no payment, see WeaponTrade) |
| `get_model() -> WeaponModel`, `get_support_grip() -> Node3D`, `get_muzzle_position()` | for rigs (left-hand IK target = Grip_L marker) |
| `get_effective()` | numbers after mods: damage, range, noise, zoom, mag_cap, suppressed ... |
| `get_mag_capacity()`, `is_armed()`, `is_firearm_equipped()` | queries |
| `get_zoom_factor()`, `get_aim_fov(base_fov)` | ADS zoom; the controller already drives the player camera FOV (below) |
| `auto_reload` (true), `crouched` (Player sets), `drive_rig_aim` (AI true / player false) | behaviour flags |

Read-only state used by HUD / camera: `reload_progress` (0..1), `current_spread` (deg, crosshair), `scope_active` (sniper fully aimed -> HUD scope overlay), `scope_sway` (Vector2 rad),
`aim_t` (ADS blend), `aim_target` (damageable under the crosshair, player only), `kick_pitch / kick_yaw` (decaying view kick in rad), `last_target`.

Camera feedback for the player is pushed straight into `Game.gameplay_camera`: `add_recoil(pitch, yaw)` per shot, `add_shake()` for heavy weapons / melee hits / explosions, and `set_fov_override()/clear_fov_override()` while aiming
with zoom >= 1.55 (marksman 2.2x, sniper 4x/8x, any scope mod). `RECOIL_CAM_SCALE` (1.0) scales weapon recoil into camera kick.

### Signals (additive)
`reload_started(id, duration)`, `recoil_kick(pitch, yaw)`, `hit_confirmed({target, killed, zone, damage, weapon, headshot})`, `melee_hit({target, damage, killed, pos})`, `grenade_thrown(node)`, `mods_changed(id)`.

### Events emitted (global bus)
`Events.gunshot(muzzle_pos, loudness, character)` (loudness = noise radius incl. suppressor x0.25), `weapon_fired(character, id)`, `weapon_changed(character, id)`, `ammo_changed(character, id, mag, reserve)` (player only),
`hit_marker(kill)` (player shots/melee that damaged something), `projectile_impact(pos, normal, surface, source)` for every bullet impact, `explosion(pos, radius, source)`, `pickup_collected(kind, amount)`, `notification` on pickups.
Crimes are NOT emitted here (WantedSystem derives them from `character_damaged / character_died / gunshot / explosion`).
`Events.character_damaged` / `died` come from CharacterBase.apply_damage as usual.

### Shooting model
* The shot leaves the muzzle (Muzzle node of the weapon model) and converges on the point where the aim ray hits (M_BULLET, shooter + vehicle excluded). The aim ray origin is slid forward to the shooter's eye plane so walls behind the camera never block it. If the muzzle pokes through a wall the bullet starts on the wall surface.
* Accuracy cone (deg) = lerp(spread, aim_spread, aim_t) x mods + movement x def.move_spread + bloom (grows per shot, decays) ; x0.7 crouched, x1.8 airborne, x1.5 in a vehicle ; AI: aim_t >= 0.7 and x lerp(3.2, 0.75, `character.ai_accuracy`) (default 0.5).
* Fire rate is phase-locked (shots/s within 0.5 %): auto, semi (0.12 s input buffer), burst (carbine: 3 shots at 16/s), pump / bolt (cycle animation + sound), shell-by-shell reload that is interrupted by firing.
* Damage per bullet/pellet = def.damage x mods x falloff(distance). The zone multiplier is applied by CharacterBase (head x3, limb x0.7, armor absorbs 70 %).
* Zones: collider/shape `meta "zone"` or hitbox node names (head/neck/arm/leg/torso/chest) first, else hit height vs `character.body_height` (default 1.8 m, 1.3 when `is_crouching`): head > 0.82 H, limb < 0.48 H. Vehicles: `tire` within 0.52 m of a `Wheel*` node, `glass` above the belt line on side/front/back faces, `engine` front third at hood height, else `body`.
* Penetration (def.penetration): glass and windows (cost 1, keep 85 %), wood / foliage (1, 62 % / 90 %), plaster / drywall / thin metal (2) are pierced; world surfaces come from collider `meta "surface"` (concrete, metal, glass, wood, dirt, sand, grass, water, flesh + aliases like asphalt/brick/steel).
* Bullets nudge loose RigidBody3D props, splash on water (plane crossing at GC.WATER_LEVEL where `WorldLayout.is_water`).
* Hit info passed to `apply_damage(amount, info)`: `source, type (bullet|melee|explosion|fire), zone, position, direction, weapon, impulse, normal, distance` (+ melee: `hit_side front|back|left|right, heavy, combo, knockdown`; explosion: `blast_center, blast_factor`).
* Victims that implement `knock_down(impulse: Vector3, duration: float)` get it for melee knockdowns and explosions; otherwise `rig.start_ragdoll()` + timed `stop_ragdoll()` (max 8 at once). Living victims also get `knockback()` and a rate-limited `rig.play_action(&"hit_react")`.

### Melee
Light / heavy (`melee_attack(heavy)`), arc cast (reach, arc, line of sight; bat heavy hits two targets). Fists combo: hit 1, 2 = 12, hit 3 = kick x1.5 with knockdown (combo window 0.95 s); heavy fists = kick + knockdown. Knife x4 from behind (victim facing away), others x1.35. Bat / crowbar heavy attacks knock down. Equipped guns fall back to the fists profile (gun-whip). Loose props are pushed. Rig actions used: `punch kick melee_swing reload throw hit_react`.

### Rig hooks (all optional - missing methods are skipped)
`rig.set_weapon_pose(def.pose)`, `rig.play_action(...)`, `rig.get_hand_socket(true)` (the model origin = grip is attached there, identity transform; barrel = -Z of the socket), `rig.set_aim()` only when `drive_rig_aim` (AI).
Without a socket the model floats at the character's chest/right hand and follows the aim (dev fallback).

## 3. Data

`WeaponDefs` (static): `get_def(id)`, `has`, `ids`, `by_category`, `shop_ids()`, `is_melee/is_firearm/is_projectile_weapon`, `mag_capacity(id, mods)`, `reserve_capacity`, `ammo_cost(id)`, `effective_fire_rate(id)`, `stat_bars(id)`, constants `CATEGORY_ORDER`, `SLOT_CATEGORIES`, `BASE` (all keys). Treat returned dictionaries as READ-ONLY. All keys are documented at the top of `weapon_defs.gd`.

| id | category | dmg | rate | mag/res | notes |
|---|---|---|---|---|---|
| fists | melee | 12 | 2.3 | - | combo, 3rd hit knockdown |
| knife / bat / crowbar | melee | 26 / 34 / 30 | 2.8 / 1.5 / 1.8 | - | backstab x4, reach 1.55 / 2.15 / 2.0 |
| pistol | handgun | 22 | 6 semi | 15/150 | vehicle_ok, $450, ammo $45 |
| revolver | handgun | 62 | 2.1 | 6/60 | vehicle_ok, $1150 |
| smg | smg | 15 | 14 auto | 30/300 | vehicle_ok, $1650 |
| shotgun_pump | shotgun | 9 x 11 | 1.15 pump | 7/56 | shell reload, $1500 |
| shotgun_auto | shotgun | 8 x 8.5 | 3.4 | 8/64 | $3100 |
| rifle_assault | rifle | 24 | 10 auto | 30/240 | $3600 |
| carbine | rifle | 21 | burst 3 @16/s | 30/240 | toggle auto, $2800 |
| rifle_marksman | rifle | 52 | 3.4 semi | 10/80 | 2.2x zoom, $4800 |
| sniper | sniper | 125 | 0.9 bolt | 5/30 | scope 4x / 8x, sway, $7200 |
| grenade | thrown | blast 230 r7.5 | - | 1+9 | cook, bounce, fuse 3 s, $130 |
| rocket_launcher | heavy | blast 340 r9.5 | 0.8 | 1/8 | 62 m/s, smoke trail, $9500 |
| grenade_launcher | heavy | blast 200 r6.5 | 1.4 | 4/24 | lobbed, contact fuse on characters/vehicles, $6600 |

`WeaponMods` (static): `MODS` (suppressor, scope, flashlight, grip, magazine_ext: name, desc, model, mount, price, multipliers), `TINTS` (10 finishes) + `TINT_PRICE`, `is_compatible(weapon, mod)`, `compatible_mods(weapon)`, `price(mod)`, `tint_color(id)`, `effective(mods)`.
Effects: suppressor noise x0.25, damage x0.92, range x0.95, flash x0.15, `shot_suppressed` sound; scope zoom x1.9 + aim spread x0.75; flashlight SpotLight3D (30 m, 30 deg) on AttRail; grip recoil and spread x0.75; extended mag capacity x1.5 (reserve cap x1.25); tint recolours the `Gun`/`GunLight` materials.

`WeaponTrade` (static, for the weapon shop / workbench UI): `buy_weapon(wc, id)`, `buy_ammo(wc, id, mags)`, `buy_mod(wc, id, mod)`, `remove_mod`, `buy_tint(wc, id, tint_id)` -> `{ok, reason, price}`; cash is spent through `Game.spend_cash`.

## 4. CombatSystem (`Game.sys(&"combat")`, static `CombatSystem.get_instance()`, `CombatSystem.get_fx()`)

* `explode(pos, radius, damage, source := null, opts := {}) -> {targets, killed, damaged}`: radial damage with falloff `(1 - d/r)^1.2` (distance to the victim's surface; vehicles use their AABB), line of sight to the victim reduces it to 30 %, delta-v impulses and torque on RigidBody3D (vehicles, props), knockback / knockdown for characters, camera shake, `Events.explosion`, `explosion_small|big` sound, FX (faceted fireball + sprites + debris + sparks + dust ring + shockwave + flash light + scorch decal). Chain reactions: a victim that explodes inside `apply_damage` re-enters `explode()` (depth-limited to 3, the rest is deferred to the next frame).
  opts: `weapon, force (delta-v at centre, default 1.7 x radius), shake, fx, scorch, fire (leave a burning patch), ignore: [Node], vehicle_mult, big`.
* `spawn_projectile(kind, def, origin, velocity, source, opts) -> Projectile`, kinds `rocket`, `grenade_launcher`, `grenade`.
* `spawn_pickup(kind, pos, amount, opts)`, `spawn_weapon_pickup(id, pos, ammo, opts)`, `drop_loot(character)`; opts `respawn` (s), `lifetime` (s), `snap` (ground snap, default true), `weapon`.
* Dead NPCs drop their firearm (+ cash) after 0.6 s: tunables `drop_weapon_chance[faction]`, `drop_cash_chance[faction]`, `max_dropped` (24).
* World pickups (health at hospital, armor at police station / viewpoint, ammo + pistol at the range, health in the park / safehouse) are placed in `post_setup()` when those `WorldLayout` locations exist; `world_pickups_enabled`.
* `spawn_fire(pos, radius, duration, source)`: burning ground with damage over time (max 6).

## 5. Lower level

* `Ballistics.shoot(space, from, dir, p) -> {hit, pos, normal, target, killed, damage, zone, surface, dist, damaged, character, water}`; `p`: `shooter, weapon, damage, range, falloff_start, falloff_min, penetration, impulse, exclude: Array[RID], mask, type, spawn_fx, sfx_budget`.
* `FxManager` (pooled, pre-warmed): `tracer(from, to, color, width, speed, length)`, `eject_shell(pos, vel, kind, ground_y)`, `impact(pos, normal, surface, strength, static_hit, play_sound)`, `blood(pos, dir)`, `smoke_puff`, `ring(pos, radius, color, dur)`, `place_decal(kind, pos, normal, size)`, `scorch(pos, r)`, `explosion(pos, radius, opts)`, `acquire_emitter(kind)/release_emitter` (rocket smoke, fire). Budget: 40 tracers, 24 shells, 40 bullet + 12 glass + 12 blood decals (64 total) + 10 scorch decals, ~150 pooled CPUParticles3D, 4 flash lights. No node allocation while firing.
* `FxRes`: procedural textures / meshes / materials (no image files).
* `Projectile.lob_velocity(origin, target)`, `Projectile.trace_arc(world, origin, vel)`.
* `CombatUtil.knock_down(victim, impulse, hit_pos, duration)`, `CombatUtil.shake_camera(strength, duration, at, max_dist)`, `MeleeResolver.strike(...)`.

## 6. Contracts expected from other modules
* Damageables implement `apply_damage(amount, info)` and are in group `damageable`; characters are `CharacterBody3D` with their collider on `L_NPC` / `L_PLAYER`, vehicles on `L_VEHICLE`.
* Optional: `character.ai_accuracy: float 0..1`, `character.body_height`, `character.is_crouching`, `victim.knock_down(impulse, duration)`, `rig.play_action(&"hit_react")`, `rig.get_hand_socket()`.
* Colliders can carry `meta "surface"` (static world) and `meta "zone"` (hitbox shapes).
* Sounds used (silent when missing): `shot_pistol shot_revolver shot_smg shot_shotgun shot_rifle shot_sniper shot_suppressed shot_rocket reload_start reload_end dry_fire melee_swing melee_hit punch hit_flesh hit_headshot hit_metal hit_concrete hit_glass hit_dirt hit_water explosion_small explosion_big grenade_bounce pickup ui_cash`.

## 7. Known limits / honest notes
* `weapons/rocket.glb` does not exist: the rocket uses a small code-built fallback shape (logged once). Pickups for health / armor / cash / ammo use code-built fallback models until `props/pickup_<kind>.glb` exist (weapon pickups use the real weapon GLBs). All weapon GLBs and `att_*` GLBs are used when present; if one is missing a code-built fallback with the same anchor nodes is used and logged.
* Particles are CPUParticles3D (radius-scaled explosions need per-use parameters); the faceted fireball shell + core are tweened meshes.
* Throw-arc preview is data only (`get_throw_preview`); no line is drawn by this module.
* Bullet-hole / glass-crack decals are only placed on static colliders (not on vehicles / characters).
* The explosion sound is a single cue; no delayed shock-wave sound.
* The hit marker / headshot ping use `Sfx.play_2d(&"hit_headshot"/&"hit_flesh")`.
* Dropped / world pickups: collection only by the player (Area3D on `L_TRIGGER`, mask `L_PLAYER`).
