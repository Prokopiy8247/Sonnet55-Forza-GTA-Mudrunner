# Shops, Interiors and Safehouse (Shops/Interiors agent)

Owner files: `gta/code/systems/{shop_system,interior_system,safehouse_system}.gd` plus helpers `interior_{room,defs,safehouse,door}.gd`,
`shop_{clerk,preview,menu_base,menu_weapons,menu_bench,menu_barber,menu_goods}.gd`, `wardrobe_{defs,menu}.gd`,
`safehouse_{sleep,garage}_menu.gd`; tests `gta/tests/shop_{interior,economy,menu,save}_test.gd`, dev tools `shop_shots.gd` (real-renderer screenshot
scenarios, args documented in its header), `shop_perf.gd` (real-renderer cost per room), `shop_tri_report.gd`, `shop_probe.gd` (GLB summary);
screenshots in `screenshots/shops/` (r2_* rooms, menus and doors, r3_/r4_/r5_ re-shoots after fixes).

Booted by Main as `Game.sys(&"shops")` (ShopSystem, which owns the InteriorSystem), `Game.sys(&"safehouse")` (SafehouseSystem);
the InteriorSystem is also `Game.sys(&"interiors")` (and `Game.sys(&"shops").interiors`).

## STATUS (keep this block current - a successor resumes from here)
Everything in the brief is implemented and was verified in the last run (headless tests: interior 94/94, economy 65/65, menu 33/33, save 21/21 = 213 PASS;
real-renderer screenshots of all 7 interiors, all 8 menus, clerk hands-up pose, safehouse at night with the TV on, garage with stored vehicles, exterior doors
open / closed; real-renderer cost measured with `shop_perf.gd`). Run the suites with
`tools\gd.ps1 exec -Script res://gta/tests/<name>.gd -Seconds 150 -GameArgs "--no-intro --no-traffic --no-peds"`.
Not done / deliberately skipped: tattoo shop (spec: lowest priority), outlines on interactables (optional), per-NPC street interaction pause is only a flag
(`Game.get_meta(&"npc_interactions_paused")`) because nobody consumes it yet. See "Known limits" at the bottom.

## InteriorSystem (class_name InteriorSystem)
Rooms are small closed boxes (`InteriorRoom`) built LAZILY on first entry (3-30 ms each) at hidden far-away positions:
`ROOM_BASE + (index * 120, 0, 0)` = x -1200.., y 12, z -1200 (outside the +-300 playable map; NOT y -400 because the Player respawns anything below
y -120 and AudioSystem switches to the underwater mix below the sea). Room shell = StaticBody3D (layer `GC.L_WORLD`): floor, ceiling, 4 walls,
faceted floor, wainscot, neon cove, ceiling light panels + 5-8 OmniLights, windows with day/night pane colour, props from `interiors/*.glb`
(`ModelLib`), a clearly labelled magenta fallback box if a GLB is missing (logged with `push_warning`, listed in `InteriorRoom.fallback_models`).

- `register_interior(id, builder: Callable(room), meta := {})` - meta: `name`, `location` (WorldLayout id -> world door), `anchor` ("Door" / "GarageDoor"),
  `hours` (bool: closed 23:00-06:00), `prompt`, `range`, `return_mode`, `sign_height`, `sign` (false = no neon OPEN/CLOSED sign).
- `enter(id, from_pos := INF, from_yaw := NAN, instant := false) -> bool` (coroutine: `await`) - fade out -> build room if needed -> teleport ->
  camera `snap_behind` -> indoor environment + audio space `&"interior"` -> fade in. Refuses in a vehicle / while `transitioning` / when dead.
- `exit(instant := false) -> bool` - back to the exact world door position + yaw, restores outdoor environment, rain, audio.
- `switch_to(id)` interior -> interior (apartment <-> garage) keeping the original world return door.
- `is_inside()`, `current_interior: StringName`, `get_room(id, build := true)`, `get_current_room()`, `door_for(id) -> InteriorDoor`,
  `door_transform(location, anchor_name, mode) -> {door, return, yaw, out}`, `is_open(id)`, `list_interiors()`, `room_origin(id)`, `get_stats()`.
- Signals: `entered(id)`, `exited(id)`.
- Flags for other systems: `Game.get_meta(&"indoors")` (bool), `Game.get_meta(&"interior_id")`, `Game.get_meta(&"npc_interactions_paused")`;
  calls `EnvironmentSystem.set_indoors(bool)` if it exists; swaps `world_environment.environment` for an indoor Environment (no fog/sun/rain, ambient colour,
  SSAO, glow) and hides `weather_fx`; `AudioSystem.set_space(&"interior"|&"auto")`, `set_duck(&"interior", x)`.
- Self healing: every 0.4 s `_sanity_check()` drops the indoor state when something else teleported the player out (respawn, debug teleport) and adopts the room when
  a save/teleport put the player inside one. `serialize()` stores `{inside, return, yaw}` only while inside.
- World doors: for every registered interior with a `location` an `InteriorDoor` (group `interactable`) sits at the GLB `Door` empty (group `landmark_anchor`,
  meta `landmark`) or at the WorldLayout location; prompt `Enter <Name>` / `<Name> - Closed (opens 06:00)`; neon `OPEN` / `CLOSED` Label3D sign above the door updates every second.
  Hospital and police_station get toast-only doors. Entering is blocked while `Game.wanted_state == &"pursuit"` with a toast.
- Hours: closed 23:00-06:00 unless the interior is `hours: false` (gas station, safehouse). `Game.cheats["shops_always_open"]` overrides.

Interiors (ids): `weapon_shop` (Gunsmith: counter + clerk, weapon_rack_wall with the real weapon models, shelf_wall, gun_bench), `clothing_store` (Threads: racks,
mannequins, mirror_wall, counter + clerk), `barber` (Clip & Co: barber chairs, mirrors, clerk), `gas_station` (Fuel Mart: shelves, counter + clerk, 24 h),
`scuba_shop` (Deep Blue: scuba racks, counter + clerk), `safehouse` (apartment: bed, nightstand, wardrobe, sofa, TV, kitchen, table + chairs, rug, stairs/door to garage),
`safehouse_garage` (3 bays, roller door, vehicle console).

`InteriorDoor` (Node3D, group `interactable`): `interact_range`, `get_interaction(player) -> {text,key,enabled}`, `interact(player)`, `on_interact`, `text_provider`, `tag`, `data`.
`ShopClerk` (CharacterBase + CharacterRig, built directly - not a Pedestrian): `raise_hands(s)`, `lower_hands()`, `mark_robbed()`, `state` (`idle hands_up robbed dead`),
`respawn()` (revived by InteriorSystem on re-entry 90 s after a kill). Damage contract implemented.

## ShopSystem (class_name ShopSystem)
Purchases return `{ok, reason, price}` and have already moved the money, played `ui_confirm` / `ui_error` / `ui_cash`-class sounds and toasts (`Game.notify`).
Free shopping debug unlock: `free_shopping = true` or `Game.cheats["free_shopping" | "free_shop" | "shop_unlock"]`.
- Weapons: `buy_weapon(id)`, `buy_ammo(id, mags)`, `buy_armor()` ($300, +100), `buy_health()` ($120, +60) - through `WeaponTrade` (owned markers, cash checks).
- Bench: `buy_mod(weapon, mod)`, `remove_mod(weapon, mod)` (free), `buy_tint(weapon, tint)` (`WeaponMods.TINTS`).
- Clothing / barber: `apply_appearance(variant_delta, persist := true)`, `get_variant()`, `reset_appearance()`, `buy_outfit(keys, wardrobe := false)`,
  `owns_item(key)`, `barber_price(hair, beard, hair_color)`, `buy_haircut(hair, beard, hair_color)`. The persistent look is `appearance` (delta over `CharacterVariants.player_default()`),
  mirrored into `Game.player.set_meta(&"appearance")` / property `appearance` and re-applied to the rig on spawn / respawn / load.
- Goods: `catalog(kind)` (`FOOD`, `SCUBA`), `buy_good(kind, id)`: snacks heal 5-50 HP, coffee / energy drink refill stamina (energy: no drain 45 s), scuba kit ($1800: sets
  meta + property `has_scuba`, a 10 min tank drains underwater and refills on the surface; drives `Game.cheats["scuba"]` while air remains), parachute pack ($600:
  `player.has_parachute`), life vest ($250, max 3, refills the lungs once on suffocation).
- Robbery: aim a firearm at the clerk inside a robbable shop (`_tick_threat`) -> hands up; `[E] Rob the register` -> $300-900 ($300-600 at the gas station),
  `Events.crime_committed(GC.CRIME_ROBBERY, door_pos, player, {witnessed, victim, witnesses, severity, weapon, shop})`, alarm light + siren, the clerk phones the police
  after 4.5-7 s (`Events.crime_reported`) when nobody else did. Cooldown 10 min per shop (`rob_cooldown_left`). A dead clerk's register can be looted too.
- Menus (registered with `Game.ui.register_menu` in `post_setup`): `shop_weapons`, `shop_bench`, `shop_clothes` (modes `store` / `wardrobe`), `shop_barber`, `shop_goods`
  (catalog `food` | `scuba`). Open with `open_menu(kind, room)` kinds `weapons bench clothes wardrobe barber food scuba`.
- Signals: `purchase_made(kind, item, price)`, `appearance_changed`, `robbery_done(shop, amount)`.
- Save: `serialize()` -> `{appearance(colors as html), owned, rob, scuba, vests, tank, stats}`; `deserialize()` tolerant of missing keys; applied after `Events.load_completed`.

Tunables (consts): `ROB_COOLDOWN_S 600`, `ROB_MIN/MAX 300/900`, `ARMOR_PRICE 300`, `HEALTH_PRICE 120`, `SCUBA_PRICE 1800`, `PARACHUTE_PRICE 600`, `VEST_PRICE 250`, `SCUBA_TANK_S 600`;
`InteriorSystem.OPEN_AT 6 / CLOSE_AT 23`, `FADE_OUT 0.3 / FADE_IN 0.42`, `ROOM_SPACING 120`.

## SafehouseSystem (class_name SafehouseSystem)
`enter_apartment()`, `enter_garage()` (both `switch_to`), `open_sleep_menu()`, `await sleep(kind := &"night", instant := false) -> hours` (`night` -> 07:00 full heal, `nap` +3 h 40 %,
`evening` -> 18:30 60 %; fade, `EnvironmentSystem.set_time`), `save_game()` (`SaveSystem.save_game(0)` + toast "Game saved"), `toggle_tv()` (looping neon screen + TV light),
`snack()` (+25 HP, 60 s cooldown), `open_wardrobe()` (free, basics + owned clothes), `open_garage_menu()`, `bring_out_vehicle(slot)` (GarageSystem `get_stored_vehicles()` / `deliver_now()`,
duck typed), `set_respawn_here(bool)`. `owned` / `respawn_here` set `Game.player` meta + property `respawn_at_safehouse`; after a hospital respawn the player is moved home
and the hospital bill is cut to 20 % (min $50). Save: `{owned, respawn_here, tv_on, last_saved}`.

## Verification (this run)
- `shop_interior_test` (94): 7 world doors within 14 m of their WorldLayout location, open / closed prompt by hour, gas station 24 h, enter + exit of every interior (position
  restored to 0.01-0.16 m, indoor flag, on floor, camera inside the room, exit door node), lazy build 3-31 ms headless (3-48 ms in the real renderer, budget 150 ms), 10 enter / exit cycles
  (no node growth under the InteriorSystem or the UI, orphan count flat), wanted-pursuit block, real fade transitions (115 ms), hospital / police toast doors, double `enter` ignored,
  exit door interactable, respawn / teleport while inside drops the indoor state and restores the outdoor Environment.
- `shop_economy_test` (65): purchases with exact cash accounting, owned / cannot-afford / free-shopping, armor, medkit, mods (suppressor noise x0.25, magazine +50 %), incompatible mod rejected,
  tint, clothing (rig dressed), wardrobe rules, barber price + purchase, JSON round trip of the appearance, appearance survives a respawn, food / energy drink / scuba (tank drains, refills) /
  parachute / life vest, robbery (aim -> hands up -> `[E] Rob` -> $300-900, `crime_committed` with witnessed flag, clerk phones in, alarm sound, cooldown, loot a dead clerk), sleep skip to 07:00,
  nap, respawn at the safehouse with a reduced fee, TV, snack, save point (slot 6, never the player's slot 0).
- `shop_menu_test` (33): the real PlayerInteraction path (prompt `[E] Enter Gunsmith` -> E -> inside), counter use points open the real menus, every menu driven through its buttons
  (buy weapon / ammo / armor, bench mod + tint, clothes buy and wear, wardrobe free, barber, food, scuba), menus pause / unpause the game, closed shop blocks entry.
- `shop_save_test` (21): REAL SaveSystem round trip (appearance, owned clothes, scuba, vests, robbery cooldown, safehouse flags, cash), save + load while standing inside the safehouse
  (the room is adopted after the load and the exit returns to the door), garage integration (stored vehicle shown in its bay with the saved paint, brought out through the roller door).
- Cost (RTX 5070, 1080p, other agents using the machine at the same time): street 1.5 ms CPU / 1.7 ms GPU, inside a room 0.6-1.1 ms CPU / ~1.7 ms GPU, 355-983 draw calls
  (the weapon shop is the heaviest: 10 real guns on the rack), 140-170 fps. Triangles (props + shell, clerk and displayed guns / cars reported separately): weapon shop 1.9k (+9.1k of rack
  guns), clothing 2.5k, barber 2.0k, gas station 1.8k, scuba 2.2k, safehouse 4.2k, garage 1.3k - above the "1500" in the brief because every Blender prop is 200-300 tris
  (the prop budget) and the generated shell is ~600; the GPU cost is negligible (see above).

## Known limits / TODO
- Room triangle counts exceed the brief's 1500 (see Verification). Merging the shell boxes into one mesh per material would remove ~500 tris and ~40 draw calls per room if ever needed.
- The sun's shadow cascades still draw the (tiny) interior casters; disabling the sun while indoors needs the Environment agent (EnvironmentSystem rewrites `sun.visible` every frame).
- The HUD minimap shows an empty circle indoors and the AIR bar is visible in every screenshot taken in the first seconds after boot (the player's `lungs` starts below `max_lungs` and regenerates; a Player / UI topic, not caused by the shops): the HUD could read
  `Game.get_meta(&"indoors")`.
- While the player is inside he is ~1.7 km from the city: street traffic / pedestrians are expected to despawn by distance and refill after the exit (not measured).
  Measured with a probe (wanted level 3 set while inside): the police keep their positions in the city (nearest unit 300+ m away); being unseen inside turns the pursuit into a search (entering a shop during a pursuit is refused with a toast).
- Clerks are `ShopClerk` (CharacterBase + CharacterRig), not Pedestrians: they do not flee through the door; they raise their hands, can be hurt / killed and come back after 90 s.
- The alarm is a procedurally generated two-tone beep (`ShopSystem.alarm_stream()`), not an entry of the Audio agent's bank.
- Shared files touched outside my ownership: none (everything is additive in my own files). Runtime-only changes to foreign nodes: `world_environment.environment` is swapped while
  indoors (restored on exit), `weather_fx.visible` is forced off indoors, `Game.cheats["scuba"]` is driven by the tank, `Game.player` gets `has_scuba` / `has_parachute` /
  `respawn_at_safehouse` properties + meta.
