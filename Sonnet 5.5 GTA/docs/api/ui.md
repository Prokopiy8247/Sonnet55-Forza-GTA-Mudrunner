# UI module (`gta/code/ui/*`) - public API

Owner: UI agent. Design space is 1920 x 1080 (project `canvas_items` stretch, `expand` aspect); everything scales with the window.
Everything is built in code (no image assets): theme, icons, widgets. Everything is **null-safe**: it lights up automatically as
Player / Weapons / Wanted / Skills / Save modules arrive.

## Files
| file | class | what |
|---|---|---|
| `ui_root.gd` | `UIRoot` (CanvasLayer, `Game.ui`) | host: HUD, wheel, menus, fades, death, waypoint, stats, settings |
| `menu_base.gd` | `MenuBase` | base class of every modal menu (frame builder, hints, confirm helper) |
| `ui_kit.gd` | `UIKit` | static widget factory (buttons, sliders, toggles, tabs, list rows, cards, bars, key caps, price tags) |
| `ui_theme.gd` | `UITheme` | `UITheme.build()` -> shared `Theme` (cyan / magenta, dark translucent rounded panels), fonts, palette, `box()` |
| `ui_icons.gd` | `UIIcons` | vector weapon silhouettes (16 ids) + location glyphs (30 ids), `weapon_info(id)` |
| `ui_draw.gd` | `UIDraw` | draw helpers (rounded rect, sector, star, shadowed text) |
| `ui_confirm.gd` | `UIConfirm` | modal yes / no dialog |
| `hud.gd`, `hud_widgets.gd` | `Hud`, `HudWidgets.*` | the in-game HUD |
| `minimap.gd`, `map_raster.gd` | `Minimap`, `MapRaster` | radar + one-shot basemap rasteriser |
| `map_screen.gd`, `ui_route.gd` | `MapScreen`, `UIRoute` | full-screen map + A* GPS route on the lane graph |
| `weapon_wheel.gd` | `WeaponWheel` | radial weapon selector (hold `weapon_wheel`) |
| `pause_menu.gd`, `status_screen.gd` | `PauseMenu`, `StatusScreen` | pause (game / status / settings / controls), skills + stats |
| `vehicle_hud.gd` | `VehicleHud` | speed dial + RPM + gear, boat, aircraft instruments |
| `damage_feedback.gd`, `death_screen.gd` | `DamageFeedback`, `DeathScreen` | vignette / desaturation / hit direction; KNOCKED OUT + BUSTED |
| `notifications.gd` | `Notifications` | toast stack + subtitles |
| `ui_showcase.gd` | `UIShowcase` | widget style guide menu (`&"ui_showcase"`) |

## UIRoot (autowired: `Game.ui`)
```
register_menu(id: StringName, menu: MenuBase)      get_menu(id) / has_menu(id)
open_menu(id, data := {}) -> bool                  close_menu()           is_menu_open() -> bool   # true for any menu OR the weapon wheel
is_input_blocked() -> bool                         # menu, wheel or confirm dialog: gameplay must ignore input
toast(text, kind := &"info")   subtitle(text, seconds)   show_prompt(text)   confirm(title, text, on_yes, on_no, yes_text, no_text)
fade(to_black: bool, seconds := 0.5, color := Color.BLACK)   # awaitable:  await Game.ui.fade(true, 0.4)
show_loading(text) / hide_loading(seconds)         # full-screen title card
set_hud_visible(bool)                              # photo mode hides the HUD (F3 does this too)
set_waypoint(Vector3) / clear_waypoint() / get_waypoint() -> Variant     waypoint, has_waypoint, route: UIRoute, signal waypoint_changed
apply_settings()                                   # re-applies Game.settings (buses, fullscreen, shadows, minimap shape)
serialize() / deserialize(d)                       # stats + waypoint (SaveSystem gathers it through Game.systems[&"ui"])
vars: hud, wheel, map_screen, pause_menu, status_screen, death, feedback, stats: Dictionary, skill_cache, capture_when_idle
```
Built-in menu ids: `&"pause"` (Esc), `&"map"` (M), `&"status"`, `&"ui_showcase"`. Registered menus of other agents (shop, garage, phone,
wardrobe, debug...) subclass `MenuBase` and call `Game.ui.register_menu(&"shop", ShopMenu.new())` in `post_setup()`.

**Menu semantics.** Opening a menu with `pauses_game == true` calls `Game.set_paused(true)` (tree paused; UI + MenuBase run `PROCESS_MODE_ALWAYS`)
and frees the mouse; closing the last menu unpauses and re-captures the mouse (`capture_when_idle`). Opening a second menu closes the first.
`Esc` (the `pause` action) closes the open menu (`closes_on_pause`, override `on_back()` to intercept); with no menu it opens the pause menu
(not while dead / busted). `M` toggles the map. `Events.menu_opened(id)` / `menu_closed(id)` fire for every menu. A menu may call its own
`close()`; the host notices through the `closed` signal.

## MenuBase
```
signal closed; var menu_id; pauses_game := true; wants_cursor := true; closes_on_pause := true; dim_background := true; data: Dictionary
open(data) / close()                                 # keep calling super in overrides
_on_open(data) / _on_close() / on_back() -> bool     # virtuals
build_frame(title, subtitle := "", width := 1040, height := 0) -> VBoxContainer body   # dim backdrop + centred panel + header + footer hints
set_title(text)  set_hints([["E","Buy"],["Esc","Close"]])  toast(text, kind)  confirm(title, text, on_yes, on_no)  focus_first()
```
## UIKit (all return styled Controls; sound `ui_click` on press)
`vbox hbox spacer label caption panel(variation) separator margin header(title, subtitle) button(text, cb, variation) tab_bar(names, cb) tab_select
slider_row(label, min, max, value, step, cb, fmt) toggle_row(label, on, cb) option_row(label, options, index, cb) stat_row bar(ratio, color, h)
scroll_list() list_row(title, subtitle, right: int|String, cb, icon_cb) price_tag(amount) keycap(text) action_key(action) card_grid(cols)
card(title, subtitle, price, icon_cb, cb)`.  Theme variations: `AccentButton DangerButton TabButton RowButton CardButton PanelHi PanelDeep
PanelFlat Pill PriceTag PriceTagBad KeyCap Title Subtle Caption`. Icon callbacks: `func(ci: Control, rect: Rect2)` -> use `UIIcons.draw_weapon(ci, id, rect, color)`.

## HUD behaviour (what it reads)
All reads are `obj.get("name")` probes - **other agents only need to keep these property names**:
* `Game.player`: `health max_health armor max_armor` (CharacterBase), `weapons`, `current_vehicle`, `stance` (`crouch cover_* parachute`), `crouching`,
  `stamina` (/ `MAX_STAMINA`), `lungs` (/ `LUNG_TIME`), `head_underwater`, `noise_radius`, `is_dead`, `is_in_vehicle()`.
* `player.weapons`: `current_id get_ammo_in_mag() get_ammo_reserve() is_aiming is_reloading reload_progress current_spread (deg) scope_active aim_target
  get_weapon_ids() inventory equip(id) get_current_def()`; `WeaponDefs.get_def(id)` -> `name category`.
* Vehicle (`current_vehicle`): `vclass display_name health max_health headlights_on siren_on input_handbrake input_throttle get_speed_kmh()
  get_forward_speed() linear_velocity` and optionally `rpm01 | rpm_ratio | engine_rpm01`, `gear | current_gear` (estimated from speed when absent).
* `Game`: `cash wanted_level wanted_state time_of_day weather cheats{show_fps, show_coords, photo_mode} settings`; `WantedSystem.get_last_known_position()`
  (+ optional `search_radius`) and `is_player_seen()`; `SkillsSystem.get_skill(id) | get_value(id) | skills{}` (0..1 or 0..100) or `Events.skill_changed`.
* Group `police` (vehicles, helis, officers; optional `vclass`), vehicles with `is_player_owned == true` get a radar glyph.
* `WorldLayout`: `roads districts water_polys building_footprints nature_zones piers airport locations lanes terrain_height()`.

Layout: top-right = cash (animated, +/- floaters), weekday / weather / clock, wanted stars (5; pursuit = solid + red/blue strip, search = flashing + escape bar
+ arc), weapon card (icon, name, mag / reserve, reload bar); bottom-left = minimap + health / armour bars; bottom-right = vehicle / aircraft instruments or
parachute altimeter; bottom-centre = stealth eye (crouching), underwater air bar, subtitles; centre = crosshair (spread, hit / kill markers, red on hostile,
sniper scope overlay), interaction prompt `[E] text`; top-centre = district banner; top-left = toasts (+ FPS / coordinates with F2).
Stamina is a ring on the minimap. Low health (< 36 %): pulsing red vignette + desaturation + pulsing bar. `Events.player_hurt` adds a hit flash and
directional indicators (source / direction from `info`).

## Events
Consumed: `cash_changed notification subtitle interaction_prompt district_changed hit_marker wanted_changed wanted_search_progress weapon_changed ammo_changed
player_hurt player_died player_busted player_respawned character_died vehicle_entered skill_changed settings_changed game_ready`.
Emitted: `menu_opened menu_closed settings_changed (settings page) game_paused (via Game.set_paused) district_changed (only when nobody emitted it within 1.5 s)`.
Sounds used (silent when missing): `ui_click ui_confirm ui_back ui_error ui_notify ui_cash ui_wasted ui_busted`.

## Input owned by the UI
`pause` (Esc), `map` (M), `weapon_wheel` (hold Tab; slows time to 0.2 and frees the mouse; release equips), `debug_overlay` (F2: FPS -> FPS + coords -> off,
writes `Game.cheats`), `photo_mode` (F3: hides the HUD), `quick_save` / `quick_load` (F5 / F9 -> `SaveSystem`; skipped when
`SaveSystem.handles_quick_keys()` returns true). Player / camera code should ignore look and fire input while `Game.ui.is_menu_open()` (already done by the Player agent).

## Death / busted
`player_died` -> time slows to 0.28, screen desaturates + red grade, "KNOCKED OUT", fade to black after 2.4 s (1.2 s fade). `player_busted` -> time 0.55, blue grade,
"BUSTED" with red / blue bar, fade after 1.7 s. `player_respawned` -> time restored, fade in over 1.3 s. 12 s failsafe releases the screen if no respawn arrives.

## Map / minimap
`MapRaster` renders the basemap once (1536 px for 640 m) when `WorldLayout.built` or roads exist and the layout signature has been stable for 1 s
(re-rendered up to 4x when the data changes; placeholder grid until then; headless keeps the placeholder). **Textures must not be created inside a
canvas draw callback (they render white) - the relief texture is created before the painter draws.** Minimap zoom follows speed / vehicle class
(85 m on foot, 105-190 m driving, 230-360 m flying, 150 m boats); blips refresh at 8 Hz, positions every frame. The full map pans / zooms, shows district
names, location icons (tier 2 icons appear when zoomed in), police, search area, GPS route and a legend; click sets / clears the waypoint (stored in
`UIRoot.waypoint`, mirrored to `Game.get_meta(&"waypoint")` and, if the property exists, `Game.waypoint`). The waypoint is cleared automatically on arrival.

## Settings (pause menu -> Settings; all keys live in `Game.settings`)
`master_volume music_volume sfx_volume` (buses `Master`, `Music`, `SFX`/`Sfx` when present), `mouse_sensitivity invert_y fov camera_shake shadows fullscreen
minimap_round traffic_density ped_density`. `Events.settings_changed` is emitted on every change; `SaveSystem.save_settings()` is called when the pause menu closes.

## Tunables
`UITheme.SAFE_X/SAFE_Y`, `WeaponWheel.SLOWMO`, `Notifications.MAX_VISIBLE/TOAST_LIFE`, `DeathScreen.KNOCKED_FADE_AT / BUSTED_FADE_AT`, `MapRaster.TEX_SIZE / MAX_REBUILDS`,
`Minimap.SIZE_PX`, `VehicleHud.DIAL_DEFAULT`.

## Tests
* `gta/tests/ui_test.gd` (headless, 73 assertions): `tools\gd.ps1 exec -Script res://gta/tests/ui_test.gd -Seconds 60 -GameArgs "--no-intro --no-traffic --no-peds"`
* `gta/tests/ui_shot.gd` + `ui_fakes.gd` (fake player / vehicles / world): `tools\gd.ps1 shot -Out screenshots\x.png -Resolution 1920x1080 -GameArgs "--exec=res://gta/tests/ui_shot.gd --ui-scene=<hud|hud_car|hud_heli|hud_plane|hud_boat|lowhp|wheel|map|pause|settings|controls|status|showcase|death|busted|stealth|chute|air> --no-intro --delay=2"`

## Known limits
* Skills page shows 0 % until `SkillsSystem` exposes `get_skill(id)` / `get_value(id)` / `skills` or emits `Events.skill_changed`.
* Save / Load buttons call `SaveSystem.save_game(0) / load_game(0)` (slot 0 only); they report "not available" while the stub returns false.
* Gamepad: wheel and map pan read the sticks directly; menus use Godot's `ui_*` focus navigation. No joypad bindings are added to the InputMap (core file).
* `Game.waypoint` does not exist in `game.gd` (core); the UI uses `Game.set_meta(&"waypoint")`. Suggested additive core change: `var waypoint := Vector3.INF`.
* The minimap draws locations from `WorldLayout.locations` through the table `UIIcons.LOC` (id -> glyph / colour / tier / label); unknown ids are skipped.
