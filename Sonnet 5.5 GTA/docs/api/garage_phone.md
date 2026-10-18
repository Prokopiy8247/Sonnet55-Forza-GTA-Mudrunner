# Garage / customization / stored vehicles / phone / photo mode (Garage agent)

Boot key `garage` -> `Game.sys(&"garage")` (`GarageSystem`, `gta/code/systems/garage_system.gd`). Menus registered in `post_setup()`:
`&"garage"` (GarageMenu), `&"garage_stored"` (GarageStoredMenu), `&"phone"` (PhoneMenu). `PhotoMode` is a child node of the system.

STATUS: complete and verified (headless tests 67 + 34 + 36 pass, real-renderer screenshots reviewed, see "Verification" / "Visual QA log").

## Files
| file | role |
|---|---|
| `systems/garage_system.gd` (`GarageSystem`) | system: bay prompt, session start, repair, stored vehicles, dealer purchase, save hooks |
| `systems/garage_session.gd` (`GarageSession`) | one customization visit: fade, move car to the studio (`VehicleBase.place_at`), orbit cam, menu, restore + exit placement |
| `systems/garage_studio.gd` (`GarageStudio`) | spot-lit photo studio room built 220 m above the bay (turntable, neon strips, key/rim spots, own Environment) |
| `systems/garage_camera.gd` (`GarageCamera`) | orbit camera (mouse drag, wheel, A/D/W/S/Q/E, idle auto-rotate, `focus()` presets) |
| `systems/garage_menu.gd` (`GarageMenu`) | the customization MenuBase (categories left, live stats / pending changes / Install right) |
| `systems/garage_build.gd` (`GarageBuild`) | paint + finish + mods dictionary; `diff_against()` = priced change list; `to_dict/from_dict` JSON |
| `systems/garage_stored_menu.gd`, `garage_interactable.gd` | stored vehicle list menu; dealer "[E] Buy" interaction point |
| `systems/vehicle_mods_visual.gd` (`VehicleModsVisual`) | builds body parts / rims / plates / livery / underglow / lamp tints / horn from `VehicleBase.mods` (installed as `VehicleBase.visual_mods_hook`) |
| `systems/vehicle_mods_fit.gd`, `vehicle_mods_meshes.gd`, `vehicle_mods_decals.gd` | body analysis (AABB, hood/roof/trunk runs, ray casts on the model), procedural livery/underglow meshes, plate textures |
| `resources/data/vehicle_mods.gd` (`VehicleModsData`) | ALL data: performance table (levels, prices, stat effects), palette, finishes, rims, parts per slot, lights, tints, plates, liveries, horns, per-vehicle config + fit overrides |
| `systems/phone_menu.gd` (`PhoneMenu`), `phone_icons.gd` | smartphone UI (P) |
| `systems/photo_mode.gd` (`PhotoMode`) | free camera photo mode (F3 / phone Camera app) |
| `tests/garage_test.gd` | headless tests (data, apply_mods numbers, cosmetics on 15 vehicles, pricing, store/deliver, serialize) |

Shared-file edits (additive): `vehicles/vehicle_base.gd` (`apply_mods` plumbing, `mod_*` fields, `visual_mods_hook`, `set_rim_color`, tyre hit counter),
`vehicles/car_vehicle.gd` (turbo, susp/shift/brake mod usage, `abs_frac` brake mod), `vehicles/vehicle_lights.gd` + `vehicle_materials.gd` (lamp tint),
`vehicles/vehicle_audio.gd` (horn style meta), `vehicles/vehicle_defs.gd` (MOD_EFFECTS).

## GarageSystem public API
```
signal stored_changed() / session_started(v) / session_ended(v) / vehicle_delivered(slot, v)
const MAX_SLOTS = 6
var unlock_all: bool                     # everything free (also Game.cheats["unlock_all_mods"])
func is_free() -> bool
func can_customize(v) -> bool            # ground car / bike / bicycle, not destroyed/flipped, implemented
# customization
func begin_session(v, site, bay) ; var session: GarageSession ; var photo: PhotoMode
func quote(base: GarageBuild, target: GarageBuild) -> Array      # [{key,label,price}]
func charge(entries) -> bool                                       # Game.spend_cash(total)
func repair_needed(v) / repair_cost(v) -> int / repair_vehicle(v, charge_money := true) -> bool
# stored vehicles (6 slots)
func get_stored_vehicles() -> Array      # [{def, name, build, health, plate, slot, out}]
func get_record(slot) -> Dictionary ; func free_slot_count() -> int
func store(v) -> int                     # slot or -1; removes the vehicle from the world; sets is_player_owned
func add_record(def_id, paint1, paint2, finish := &"gloss", mods := {}) -> int
func remove(slot) -> bool
func deliver(slot, delay := 4.0) -> VehicleBase   # coroutine (await): toast, delay, spawn on a road point 50-130 m away out of view
func deliver_now(slot, at: Transform3D = null, silent := false) -> VehicleBase
# dealer
func buy_dealer_vehicle(v) -> int ; func buy_vehicle(def_id, paint1, paint2, finish) -> int   # Game.spend_cash(price) + stores in a free slot
# phone / photo
func toggle_phone() / phone_available() / start_photo_mode() / open_stored_menu(site_id)
# save
func serialize() -> Dictionary / deserialize(data)    # {"version":1,"slots":[null|{def,name,build,health,slot,plate,out?}]}
```
Vehicle side: `VehicleBase.apply_mods(mods: Dictionary)`, `VehicleBase.mods`, `mod_power mod_brake mod_grip mod_shift mod_susp mod_downforce
mod_turbo_boost mod_turbo_spool mod_tire_hits damage_taken_mult bulletproof_tires`, `VehicleFactory.spawn(id, xf, {"mods":..., "paint":..., "paint2":..., "finish":...})`.

## Mods dictionary (VehicleBase.mods == GarageBuild.mods)
Performance levels (int): `engine(0-4) brakes(0-3) suspension(0-3) transmission(0-3) turbo(0-1) armor(0-5) tires(0-3) spoiler(0-3 aero) weight(0-2)`.
Cosmetic keys: `p_<slot>` (slots spoiler front_bumper rear_bumper hood roof skirts exhaust grille mirrors; value = option id), `rim_style`, `rim_color`(Color),
`headlight`, `taillight`, `underglow`, `plate`, `plate_text`, `livery`, `livery_color`(Color), `horn`(int), `window_tint`(0-3). A missing key means stock.
Stat effects are listed in `VehicleModsData.performance()[i].fx` (power, brake, grip, susp_freq, shift_time, damage_taken, downforce, mass, health,
turbo_boost, turbo_spool, tire_hits) and are the single source for `VehicleBase.apply_mods` and the garage UI bars (`VehicleModsData.stat_summary`).

## Prices
Per-level prices in the data file; vehicle-class multiplier `VehicleModsData.price_mult(def_id)` (compact 0.8 ... firetruck 1.8), rounded to $10.
Paint $350 per colour, finishes $0-2400. Downgrades are free and not refunded. Repair = damage fraction * clamp(price*0.12,150,5000) + $60 per flat tyre
+ $90 per glass state. Phone mechanic = repair + $40 call-out. Delivery of a destroyed car = $500 insurance. Everything free with `unlock_all`.

## Events
Emits `Events.interaction_prompt` (bay prompt "[E] Customize ..."), `Events.photo_taken(path)` (PhotoMode). Listens `Events.vehicle_destroyed`.

## Controls
Bay prompt `[E] Customize <vehicle>` (drive a car / bike into a bay of the garage_shop, below 14 km/h) -> session. In the garage: drag LMB/RMB = orbit,
wheel = zoom, A/D rotate, W/S tilt, Q/E zoom, Esc = leave (asks to discard unpaid changes). `[E] Garage - store <vehicle>` near the safehouse garage door.
`P` = phone (does NOT pause; Esc / P closes, Backspace = back). `F3` = photo mode (also phone Camera app): LMB orbit, MMB/Shift pan, wheel dolly,
WASD+QE fly, Z/C roll, Tab hide panel, Enter/F12/Space shoot, F3/Esc exit.

## Phone apps
Services (Taxi -> `Game.sys(&"transit").call_taxi()` if present else a toast; Vehicle service = slot picker -> `GarageSystem.deliver`; Mechanic = $40 call-out +
repair cost, 3.5 s delay), Vehicles (slot list, Deliver / Locate), Camera (PhotoMode), Map (`Game.ui.open_menu(&"map")`), Quick Save (`SaveSystem.save_game(0)`),
Radio (`AudioSystem.get_stations/get_station/set_station/radio_off`, duck typed), Settings (master/music/sfx volume, camera shake, fps counter), Stats.
Everything degrades to a toast when the system behind it is missing. Content sits in a clipping holder so no page can stretch the device frame.

## Photo mode
Free orbit/fly camera started where the gameplay camera is. FOV 15-110 (slider), roll +-45 (slider; keys Z/C reach +-60), depth of field (CameraAttributesPractical, auto focus on the pivot distance or manual),
filter presets neutral / vivid / noir / sunset (Environment adjustment + colour-correction LUT on a DUPLICATE of the world environment, so nothing leaks),
time of day is held (game paused), HUD hidden, player input locked. `take_photo()` (coroutine) saves `user://photos/photo_<timestamp>.png`, shows a thumbnail +
toast with the path and emits `Events.photo_taken(path)` and `PhotoMode.photo_saved`. Exit restores pause state, HUD, input, camera and mouse mode.

## Tunables (constants / vars)
`GarageSystem`: `MAX_SLOTS=6`, `BAY_HALF_WIDTH=3.5`, `DELIVERY_INSURANCE=500`, `unlock_all`. Bay prompt speed limit 14 km/h (`_update_bay_prompt`).
`GarageSession.STUDIO_LIFT=220` (studio height above the bay). `GarageStudio`: room 26x26x9, key spot 16, fill omnis, one-shot ReflectionProbe (layer 20 = studio
only, the car never reflects itself), reflection-only softboxes (layer 20, invisible to the garage camera). `GarageCamera`: `screen_shift` (set by the menu so the car
sits in the free gap between the panels), `physics_interpolation_mode = OFF`. `PhoneMenu.MECHANIC_FEE=40`. Data/prices/stat effects: `VehicleModsData` only.
`VehicleModsData.FIT_OVERRIDES` (per vehicle/slot dx dy dz s sx sz pitch) is EMPTY: the contact-sheet QA showed every part fitting on all 15 ground vehicles.

## Verification
Headless (all green in the last run):
- `exec -Script res://gta/tests/garage_test.gd -Seconds 240 -GameArgs "--no-traffic --no-peds --no-intro"` : 67 PASS (data consistency, apply_mods numbers, measured
  0-100 / braking / top speed deltas, tyre durability, cosmetics on 15 vehicles + removal, pricing, cash accounting, store / deliver, dealer points, serialize round trips).
  Measured (sedan): stock 0-100 7.02 s / brake 36.2 m / top 188 km/h; tuned (engine 4, trans 3, turbo, brakes 3, tyres 2, susp 3, weight 2) 4.73 s / 28.5 m / 204.6 km/h;
  brakes-only 32.3 m.
- `exec -Script res://gta/tests/garage_flow_test.gd -Seconds 120 -GameArgs "--no-traffic --no-peds --no-intro"` : 34 PASS (real bay: prompt -> E key event -> lock / fade /
  studio / menu / all 10 pages build -> repair pays -> preview free -> revert -> refused without cash -> install pays the quote -> unconfirmed paint dropped on exit ->
  car at the bay exit, control restored -> store from session -> deliver with mods).
- `exec -Script res://gta/tests/phone_test.gd -Seconds 90 -GameArgs "--no-traffic --no-peds --no-intro"` : 36 PASS (P key, every app page, vehicle service delivery,
  mechanic cost, taxi / map graceful, photo mode F3 enter / filters / DOF / save file / event / exit restores everything, blocked while a menu is open, phone Camera app).
Renderer: `tools\gd.ps1 shot -Out screenshots\garage\x.png -Resolution 1920x1080 -GameArgs "--no-intro --exec=res://gta/tests/garage_shots.gd --gs-mode=<sheet|menu|one|phone|photo|bay|perf|dealer>"`
(`garage_shots.gd` header lists its options). Performance (1080p, RTX 5070): garage studio with a fully modded car 176 fps avg (min 153, ~400 draw calls),
garage menu pages 178 fps, phone open / photo mode (with DOF) at the 180 fps cap of the display.

## Visual QA log (what was looked at and fixed)
- Contact sheets of all 15 ground vehicles x 4 option sets (every body part, rim, livery, underglow, plate, tint) from front and rear 3/4: parts mount on all bodies
  (sedan, compact, sports, muscle, suv, pickup, van, taxi, police, ambulance, firetruck, truck, tactical, motorcycle, bicycle); no override table entries were needed.
- Fixed this pass: studio was far too dark (paint read as black) -> lighter walls, stronger key + two fills, ReflectionProbe + softboxes, no floor glare;
  garage panel width jumped between pages (sliders / swatches / plate preview forced min widths) -> clipping holder + compact rows, camera `screen_shift` centres the car in the gap;
  side-view presets cropped the car; photo / garage cameras lagged behind jumps because of physics interpolation while paused (frames mid-lerp) -> interpolation OFF;
  phone Vehicle service / Settings pages stretched the phone out of its frame -> clipping holder, compact slot rows, duplicate "Radio Off" row removed;
  performance page upgrade buttons were clipped -> "+ <level name>".
- Brake upgrade did nothing measurable (stock brakes already sit at the ABS grip limit) -> `CarVehicle` raises the usable ABS fraction with `mod_brake`.

## Fallbacks / known limits
- Fallbacks: NONE in use (`VehicleModsVisual.fallbacks_used` is empty; all 19 body-part GLBs + 10 wheel GLBs come from `models/vehicle_parts`). If a GLB is missing the option is skipped with `push_warning`.
- Underglow is a procedural glow mesh (no GLB). Livery stripes are procedural geometry draped on the body (VehicleModsFit), plates are generated textures.
- Only ground vehicles are customizable (cars, bikes, bicycle); aircraft and boats are refused by `can_customize`.
- Horn variants reuse existing Sfx horn sounds (`horn_truck`, `horn_fire`, `horn_bike`, pitched); missing ones are silent.
- Delivery picks a lane-graph point 50-130 m away out of the camera frustum; with no lane graph it drops the car 14 m in front of the player.
- A stored vehicle that is out in the world is serialized with its position and re-spawned on load; a destroyed one costs $500 insurance to replace.
