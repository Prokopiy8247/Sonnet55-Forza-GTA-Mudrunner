# Audio module (`gta/code/audio/*`) - API

All sound in Halcyon Bay is **original and procedurally synthesised in GDScript** (no samples, nothing downloaded).
Owner: Audio agent. Tests: `gta/tests/audio_test.gd` (exec, 79 checks), `audio_drive_test.gd` (exec with `--vehicle=sports`, real player + car), `audio_dev.gd` / `audio_radio_dev.gd` (script, developer loops: stats, WAV and spectrogram export).
WAV + spectrogram exports of key sounds: `screenshots/audio_check/`.

## 1. Quick start for other modules

```gdscript
Sfx.play_3d(&"shot_pistol", muzzle_pos)                         # positional one-shot, default range = the sound's natural range
Sfx.play_3d(&"hit_metal", hit_pos, -2.0, randf_range(0.9, 1.1)) # volume dB, pitch scale
Sfx.play_3d(&"horn_car", vehicle.global_position, 0.0, 1.0, 140.0, vehicle)  # last arg: follow a moving node
Sfx.play_2d(&"pickup")                                          # non-positional world/player feedback
Sfx.play_ui(&"ui_confirm")                                      # HUD / menu (UI bus, always audible, works while paused)
var p := Sfx.create_player_3d(&"siren_police", vehicle, -3.0, 320.0, true)   # own looping player (not pooled), caller owns it
var snd := EngineSound.create(EngineSound.profile_for(vehicle.def_id)); vehicle.add_child(snd)
snd.update(rpm01, load01)                                       # every physics frame while the engine runs
```

Everything tolerates missing sounds (silent + one warning per unknown id). Common alternative ids are aliased
(`shot_carbine -> shot_rifle`, `explosion -> explosion_big`, `step_gravel -> step_sand`, ... see `Sfx.ALIASES`).

## 2. `Sfx` autoload (`sfx.gd`)

| member | description |
|---|---|
| `play_ui(id, db := 0.0)` | non-positional, bus `UI`, ignores distance |
| `play_2d(id, db := 0.0, pitch := 1.0) -> AudioStreamPlayer` | non-positional world sound (bus of its category) |
| `play_3d(id, pos, db := 0.0, pitch := 1.0, max_distance := 80.0, follow: Node3D = null) -> AudioStreamPlayer3D` | pooled positional one-shot. Passing the default `80.0` means "use the sound's natural range" (`meta.range`, e.g. 170 m gunshots, 420 m explosions). Returns `null` when culled / dropped. Looping streams (horns, sirens, skid) auto-stop after their `oneshot` length (0.45-8.8 s). The returned player is pooled: do not keep it after it finishes. |
| `create_player_3d(id, parent, db := 0.0, max_distance := 120.0, autoplay := false)` | NON-pooled `AudioStreamPlayer3D` child of `parent` with the correct stream/bus/unit size, for long running loops (sirens on a vehicle, skid, alarms). Caller starts/stops/frees it. |
| `get_stream(id) -> AudioStream` | `AudioStreamRandomizer` for multi-variant one-shots (random variant + pitch/volume jitter), the `AudioStreamWAV` for loops / single variants. Blocks only if the sound is still being generated. |
| `get_wav(id, variant := 0)`, `get_variant_count(id)`, `is_loop(id)`, `get_bus(id)`, `get_range(id)` | raw access / metadata |
| `has_sound(id)`, `sound_ids()`, `is_sound_ready(id)`, `is_bank_ready()`, `wait_ready()`, signal `bank_ready` | registry / generation state |
| `stop_voice(player, fade := 0.0)`, `stop_all()` | stop pooled voices |
| `was_played_recently(cat_or_id, pos, within := 0.15, radius := 12.0)` | used by the safety nets; other modules may use it to avoid doubling |
| `set_bus_duck(bus, db)`, `get_bus_fx(bus)`, `apply_settings()` | bus helpers (menus/underwater logic lives in AudioSystem) |
| `stats()` | `{played, culled, stolen, dropped_poly, dropped_unready, missing, gap, active_3d, active_2d, bank_gen_ms, ...}` |
| `listener_pos`, `listener_valid`, `enabled` | listener = current Camera3D, updated every frame; `enabled = false` mutes all pooled playback |

**Polyphony / priority.** 32 pooled 3D voices + 14 pooled 2D voices. Every sound has `poly` (max simultaneous voices of the same id, e.g. 4
for gunshots) and `cat_poly` (per category, e.g. 14 weapons, 10 footsteps). When a cap or the pool is full the *least important* voice
(category priority 1..10 x 100 - distance in metres) is stopped if the new one outranks it, otherwise the new sound is dropped. Explosions
(priority 10) always play; footsteps (1) are the first to go. `gap` rejects a re-trigger of the same id inside a few ms (footsteps 70 ms).
Random pitch (+-2.5..8 %) and volume (+-0.5..2 dB) variation is applied per category; multi-variant sounds never repeat the same variant twice in a row.

**Buses** (created at boot, the project ships no bus layout): `Master` (hard limiter) > `SFX` (reverb send + low-pass slot), `Engine`, `Voice`,
`Ambience`, `Music` > `Radio` (low-pass slot), `UI`. Volumes come from `Game.settings` (`master_volume`, `sfx_volume`, `music_volume`; optional
`ambience_volume`, `voice_volume`, `ui_volume`, `radio_volume`, default 1.0) and are re-applied on `Events.settings_changed`.
Modules running their own players should use `Sfx.get_bus(id)` for the bus name.

**Generation.** On boot all 132 ids (232 buffers, about 350 s of audio) are loaded from `res://gta/generated/audio/<id>_<variant>.res` when a bake with a
matching source fingerprint exists (**all 232 buffers ready about 80 ms after boot, on worker threads**), otherwise synthesised on `WorkerThreadPool`
(5 low-priority tasks; about 6 s wall / 24 s CPU) and the game works in the meantime (a sound requested before it exists is generated
inline if nobody started it, or dropped if a worker is building it). Re-bake after changing any recipe:
`powershell -NoProfile -File tools\gd.ps1 script -Script res://gta/code/editor/audio_bake.gd -Seconds 120 -GameArgs "all"` (`clean`, `wipe`, `ids=a,b` also exist).
A stale bake is detected automatically (md5 of the recipe sources stored in each file) and ignored. The bake is about 10 MB.

## 3. `EngineSound` (`engine_sound.gd`, `class_name EngineSound extends Node3D`)

```gdscript
var snd := EngineSound.create(&"car_v8")      # profiles: car_small car_v6 car_v8 sports truck bike boat heli_rotor prop_plane jet
vehicle.add_child(snd)
snd.update(rpm01, load01)                      # rpm01 0 = idle .. 1 = redline (rotor / propeller speed for aircraft), load01 = throttle (collective)
snd.start(with_ignition := false) / snd.stop(with_shutdown := false)   # optional: update() auto-starts when rpm/load > 0, stop() fades out
EngineSound.profile_for(&"muscle")             # suggested profile for a VehicleDefs id
```
Public vars: `running`, `volume_db` (per-vehicle trim), `max_distance` (95 m cars, 260 m heli/jet), `doppler`, `profile`.

Design: 3-4 seamless loops per profile rendered at log-spaced firing frequencies; `update()` maps rpm to a target firing frequency, cross-fades the two
neighbouring loops (equal power, weights biased brighter under load) and sets `pitch_scale` (0.5-2.6) / `volume_db` on `AudioStreamPlayer3D`s on bus
`Engine`. Extras: whine / turbo / turbine layer, **gear-shift dip + thunk** (rpm falls fast under load), **exhaust burble on lift-off** (v8, sports, bike),
turbo blow-off, distance LOD (beyond 38 m only the dominant loop; beyond `max_distance` everything is paused), doppler only when the source is more than
14 m from the camera. Measured `update()` cost: about 10 us. Helicopter rotor chop rate scales with `rpm01` (5 -> 14.5 Hz blade pass), propeller drone
24 -> 82 Hz, jet whine/roar pitch follows `rpm01`.
If the Vehicles module does not attach engine sounds, AudioSystem attaches one automatically to every vehicle with `engine_on` within 110 m
(`AudioSystem.auto_engine_sounds`; it stands down permanently as soon as it sees a vehicle that already has an `EngineSound`).

## 4. `AudioSystem` (`audio_system.gd`, system key `audio`)

Ambience, bus effects, radio API, safety nets. Everything is optional for other modules except the radio selection calls.

* **Ambience beds** (crossfaded, 1-2 s): city hum + distant traffic, wind (weather/altitude/coast), sea waves (coast proximity from `WorldLayout.is_water`
  rings), rain light/heavy (`Game.rain_intensity`), industrial machinery, park leaves, night crickets, crowd murmur (non-verbal babble, pedestrians in range),
  airport, underwater. Driven by `Game.get_district`, `Game.weather`, `Game.rain_intensity`, `Game.daylight()`, camera altitude, player in vehicle (cabin muffling).
* **Scheduled one-shots**: gulls (coast, day), birds (park/residential, day), industrial clanks, ship horn, thunder (storm / heavy rain), **distant sirens**
  (moving source; every 11-26 s while `wanted_level > 0`, rarely otherwise; police / ambulance / fire).
* **Underwater**: `set_underwater(bool)` (also auto-detected when the camera is below `GC.WATER_LEVEL`): 680 Hz low-pass on SFX/Engine/Voice/Music, surface beds fade out, underwater bed fades in.
* **Ducking**: menus (`Events.menu_opened/closed`, `Game.ui.is_menu_open()`), weapon wheel held, `game_paused`, and `set_duck(key, strength)` for other modules; strongest wins (no stacking); a low-pass darkens SFX/Engine/Ambience.
* **Reverb send** follows the district (downtown 0.15 wet, park 0.03 ...) or `set_space(&"interior" | &"garage" | &"tunnel" | &"street" | &"open" | &"auto")`.
* **Helpers**: `get_listener_position()`, `get_listener_forward()`, `position_around_listener(min, max, hmin, hmax)`, `play_distant_siren(kind)`, `trigger_thunder(close)`, `attach_engine_sound(vehicle)`, `get_status()`.
* **Vehicle sirens**: every vehicle with `siren_on` within 260 m gets a looping siren player (police wail / yelp, ambulance two-tone, fire wail) unless a
  `siren*` stream already exists on the vehicle; stopped when `siren_on` turns off.
* **Safety nets** (`safety_net := true`): `weapon_fired`, `explosion`, `vehicle_collision`, `character_died`, `character_damaged` (hurt grunt + hit_flesh/headshot), `vehicle_entered/exited`
  (doors), `vehicle_horn`, `wanted_changed`, `player_busted`, `player_died`, `pickup_collected` play their sound one frame later **only if** `Sfx.was_played_recently()` shows
  gameplay code did not already play a sound of that kind there. Modules that play their own sounds are never doubled.

### Radio
`AudioSystem.radio_next()`, `radio_prev()`, `set_station(id)`, `get_station()`, `get_station_name([id])`, `get_stations()`, `radio_off()`, `is_radio_playing()`, `get_radio_info()`.

Stations: `halcyon_fm` (Halcyon FM - chill synthwave, 98 bpm A minor), `lofi_harbor` (Lo-Fi Harbor - swung boom-bap with FM electric piano, vinyl crackle, 76 bpm),
`calle_funk` (Calle Funk 99.1 - latin funk, clave/congas/clavinet/horn stabs, 108 bpm D dorian), `neon_static` (Neon Static - electro night drive, 122 bpm F# minor), and `off`.
Each station is a seeded generative sequencer (chord progressions per 4-bar phrase, bass/arp/lead patterns, motif repetition + mutation, fills, 8-phrase song form, sidechain
pump, delay + reverb); a worker thread renders stereo phrases (2-9x realtime) two ahead into a queue and `RadioPlayer` streams them gap-free through an `AudioStreamGenerator`
(22.05 kHz) on bus `Radio`. Station switching plays a tuning-static sound and the station ident jingle. The radio is audible only while the **player is in a vehicle whose
`engine_on` is true** (not bicycles); after leaving, that vehicle's radio stays on **low-passed (650 Hz) and quiet, fading out over 32 m**. The `radio_next` / `radio_prev` input
actions (`.` `,`) are handled while driving (debounced 120 ms). The choice is stored in `Game.settings["radio_station"]` and `Events.radio_station_changed(station_id)`
is emitted on every change and when the player gets into a car. Warm-up: 2.5 s after boot the first phrase of every station is rendered in the background.

## 5. DSP toolkit (`synth.gd`, `audio_analysis.gd`)
`Synth` (static, thread-safe, `const Synth = preload("res://gta/code/audio/synth.gd")`): oscillators (sine/saw/square/triangle, polyBLEP, per-sample frequency, sweeps, FM, additive),
noise (white/pink/brown, smooth random, crackle), envelopes (ADSR, exponential, breakpoints, swell), filters (one-pole, RBJ biquad LP/HP/BP/notch/peak/shelf, swept cutoff, formant bank,
circular filtering for loops), delay/echo taps/comb/allpass/Schroeder reverb, distortion (tanh, clip, fold, bit-crush, limiter), resampling, granular, glottal voice source, modal synthesis,
loop crossfade, `to_wav` (16-bit mono `AudioStreamWAV`, loop points), `save_wav_file`. `AudioAnalysis`: FFT, spectrum, centroid, band energy, zero-crossings, RMS envelope / decay time,
pitch tracks (spectral + autocorrelation), loop-seam metrics, spectrogram PNG (`plot`). 16-bit mono PCM; 22.05 kHz, dark/low sounds 16 kHz or 11.025 kHz.

## 6. Sound ids
Sound recipes live in `bank_ui.gd`, `bank_weapons.gd`, `bank_character.gd`, `bank_vehicle.gd`, `bank_world.gd`, `bank_engine.gd`; registry + metadata + bake in `sound_bank.gd`.
"range" = natural audible distance used for the default `max_distance`; "unit" = 3D unit_size (m of full level, -6 dB per doubling beyond).
All contract ids of docs/ARCHITECTURE.md section 8 exist (`audio_test` checks them); extras: `step_metal`, `horn_fire`, `siren_police_yelp`, `engine_burble`, `engine_shift`, `radio_tune`, `gull`, `bird`, `clank`, `ship_horn`, `eng_*`, `amb_*`.
Notes: `horn_*`, `siren_*`, `skid` are LOOPS (horns: 70 ms attack then a 0.5 s loop region) - `play_3d` gives a beep / burst of the sound's `oneshot` length, or use
`create_player_3d` / `get_stream` and stop them yourself.


### UI / HUD

| id | category | variants | loop | length s | rate Hz | bus | range m | unit m |
|---|---|---|---|---|---|---|---|---|
| `ui_click` | ui | 1 | - | 0.07 | 22050 | UI | 0 | 10 |
| `ui_back` | ui | 1 | - | 0.09 | 22050 | UI | 0 | 10 |
| `ui_error` | ui | 1 | - | 0.44 | 22050 | UI | 0 | 10 |
| `ui_confirm` | ui | 1 | - | 0.75 | 22050 | UI | 0 | 10 |
| `ui_cash` | ui | 1 | - | 1.00 | 22050 | UI | 0 | 10 |
| `ui_notify` | ui | 1 | - | 1.20 | 22050 | UI | 0 | 10 |
| `ui_wanted_up` | ui | 1 | - | 1.90 | 22050 | UI | 0 | 10 |
| `ui_wanted_down` | ui | 1 | - | 1.60 | 22050 | UI | 0 | 10 |
| `ui_busted` | ui | 1 | - | 2.60 | 22050 | UI | 0 | 10 |
| `ui_wasted` | ui | 1 | - | 3.40 | 22050 | UI | 0 | 10 |
| `radio_tune` | ui | 1 | - | 0.42 | 22050 | UI | 0 | 10 |

### Weapons, melee, impacts, explosions

| id | category | variants | loop | length s | rate Hz | bus | range m | unit m |
|---|---|---|---|---|---|---|---|---|
| `shot_pistol` | weapon | 3 | - | 1.05 | 22050 | SFX | 170 | 18 |
| `shot_revolver` | weapon | 2 | - | 1.60 | 22050 | SFX | 170 | 22 |
| `shot_smg` | weapon | 3 | - | 0.67 | 22050 | SFX | 170 | 16 |
| `shot_shotgun` | weapon | 2 | - | 2.00 | 22050 | SFX | 170 | 26 |
| `shot_rifle` | weapon | 3 | - | 1.73 | 22050 | SFX | 170 | 28 |
| `shot_sniper` | weapon | 2 | - | 3.95 | 22050 | SFX | 320 | 45 |
| `shot_suppressed` | weapon | 3 | - | 0.47 | 22050 | SFX | 60 | 7 |
| `shot_rocket` | weapon | 1 | - | 2.30 | 16000 | SFX | 260 | 40 |
| `reload_start` | weapon_mech | 2 | - | 0.42 | 22050 | SFX | 26 | 6 |
| `reload_end` | weapon_mech | 2 | - | 0.42 | 22050 | SFX | 26 | 6 |
| `dry_fire` | weapon_mech | 2 | - | 0.14 | 22050 | SFX | 26 | 6 |
| `melee_swing` | melee | 3 | - | 0.32 | 22050 | SFX | 32 | 6 |
| `melee_hit` | melee | 3 | - | 0.35 | 22050 | SFX | 32 | 6 |
| `punch` | melee | 3 | - | 0.30 | 22050 | SFX | 32 | 6 |
| `hit_flesh` | impact | 3 | - | 0.30 | 22050 | SFX | 48 | 6 |
| `hit_headshot` | impact | 2 | - | 0.35 | 22050 | SFX | 48 | 6 |
| `hit_metal` | impact | 3 | - | 0.60 | 22050 | SFX | 48 | 6 |
| `hit_concrete` | impact | 3 | - | 0.40 | 22050 | SFX | 48 | 6 |
| `hit_glass` | impact | 2 | - | 0.55 | 22050 | SFX | 48 | 6 |
| `hit_dirt` | impact | 3 | - | 0.30 | 22050 | SFX | 48 | 6 |
| `hit_water` | impact | 3 | - | 0.35 | 22050 | SFX | 48 | 6 |
| `explosion_small` | explosion | 2 | - | 2.80 | 16000 | SFX | 420 | 60 |
| `explosion_big` | explosion | 2 | - | 4.70 | 16000 | SFX | 420 | 110 |
| `grenade_bounce` | impact | 2 | - | 0.50 | 22050 | SFX | 48 | 6 |
| `glass_break` | impact | 2 | - | 1.20 | 22050 | SFX | 80 | 18 |

### Character: steps, foley, voice

| id | category | variants | loop | length s | rate Hz | bus | range m | unit m |
|---|---|---|---|---|---|---|---|---|
| `step_concrete` | step | 4 | - | 0.20 | 22050 | SFX | 28 | 3 |
| `step_grass` | step | 4 | - | 0.24 | 22050 | SFX | 28 | 3 |
| `step_sand` | step | 4 | - | 0.26 | 22050 | SFX | 28 | 3 |
| `step_wood` | step | 4 | - | 0.28 | 22050 | SFX | 28 | 3 |
| `step_water` | step | 3 | - | 0.36 | 22050 | SFX | 28 | 3 |
| `step_metal` | step | 3 | - | 0.30 | 22050 | SFX | 28 | 3 |
| `splash` | foley | 3 | - | 0.80 | 22050 | SFX | 45 | 8 |
| `splash_big` | foley | 2 | - | 1.50 | 16000 | SFX | 80 | 18 |
| `jump` | foley | 3 | - | 0.26 | 22050 | SFX | 45 | 5 |
| `land` | foley | 3 | - | 0.30 | 22050 | SFX | 45 | 5 |
| `hurt_m` | voice | 4 | - | 0.42 | 22050 | Voice | 55 | 7 |
| `hurt_f` | voice | 4 | - | 0.48 | 22050 | Voice | 55 | 7 |
| `death_m` | voice | 3 | - | 1.35 | 22050 | Voice | 55 | 7 |
| `death_f` | voice | 3 | - | 1.25 | 22050 | Voice | 55 | 7 |
| `breath_hard` | voice | 2 | - | 1.30 | 22050 | Voice | 55 | 3 |
| `gasp` | voice | 2 | - | 0.55 | 22050 | Voice | 55 | 4 |
| `scream` | voice | 3 | - | 1.45 | 22050 | Voice | 110 | 20 |
| `cough` | voice | 2 | - | 0.70 | 22050 | Voice | 55 | 7 |
| `door_open` | foley | 2 | - | 0.70 | 22050 | SFX | 45 | 8 |
| `door_close` | foley | 2 | - | 0.50 | 22050 | SFX | 45 | 8 |
| `pickup` | foley | 1 | - | 0.75 | 22050 | SFX | 45 | 6 |

### Vehicles, horns, sirens, engine accents

| id | category | variants | loop | length s | rate Hz | bus | range m | unit m |
|---|---|---|---|---|---|---|---|---|
| `horn_car` | horn | 1 | loop | 0.57 | 22050 | SFX | 150 | 22 |
| `horn_truck` | horn | 1 | loop | 0.57 | 22050 | SFX | 150 | 32 |
| `horn_bike` | horn | 1 | loop | 0.57 | 22050 | SFX | 150 | 16 |
| `horn_fire` | horn | 1 | loop | 0.57 | 22050 | SFX | 150 | 45 |
| `skid` | vehicle | 2 | loop | 1.08 | 22050 | SFX | 95 | 14 |
| `crash_light` | vehicle | 3 | - | 1.10 | 22050 | SFX | 95 | 18 |
| `crash_heavy` | vehicle | 2 | - | 2.00 | 22050 | SFX | 170 | 35 |
| `siren_police` | siren | 1 | loop | 3.20 | 22050 | SFX | 260 | 40 |
| `siren_police_yelp` | siren | 1 | loop | 1.12 | 22050 | SFX | 260 | 40 |
| `siren_ambulance` | siren | 1 | loop | 2.00 | 22050 | SFX | 260 | 40 |
| `siren_fire` | siren | 1 | loop | 4.40 | 22050 | SFX | 260 | 40 |
| `door_vehicle_open` | vehicle | 2 | - | 0.55 | 22050 | SFX | 95 | 8 |
| `door_vehicle_close` | vehicle | 2 | - | 0.55 | 22050 | SFX | 95 | 10 |
| `ignition` | vehicle | 2 | - | 1.90 | 22050 | SFX | 95 | 10 |
| `engine_off` | vehicle | 1 | - | 0.90 | 22050 | SFX | 95 | 9 |
| `turbo_whistle` | engine_fx | 1 | - | 1.20 | 22050 | Engine | 75 | 10 |
| `engine_burble` | engine_fx | 4 | - | 0.85 | 22050 | Engine | 75 | 16 |
| `engine_shift` | engine_fx | 2 | - | 0.22 | 22050 | Engine | 75 | 8 |

### Ambient one-shots

| id | category | variants | loop | length s | rate Hz | bus | range m | unit m |
|---|---|---|---|---|---|---|---|---|
| `gull` | ambient_shot | 4 | - | 1.44 | 22050 | Ambience | 140 | 30 |
| `bird` | ambient_shot | 5 | - | 1.10 | 22050 | Ambience | 140 | 22 |
| `clank` | ambient_shot | 4 | - | 1.90 | 16000 | Ambience | 140 | 35 |
| `ship_horn` | ambient_shot | 2 | - | 4.60 | 16000 | Ambience | 450 | 120 |
| `thunder` | ambient_shot | 3 | - | 6.30 | 11025 | Ambience | 1000 | 400 |

### Ambience beds (AudioSystem, loops)

| id | category | variants | loop | length s | rate Hz | bus | range m | unit m |
|---|---|---|---|---|---|---|---|---|
| `amb_city` | amb_loop | 1 | loop | 12.00 | 16000 | Ambience | 100 | 20 |
| `amb_wind` | amb_loop | 1 | loop | 13.50 | 16000 | Ambience | 100 | 20 |
| `amb_sea` | amb_loop | 1 | loop | 14.00 | 16000 | Ambience | 100 | 20 |
| `amb_rain_light` | amb_loop | 1 | loop | 7.70 | 22050 | Ambience | 100 | 20 |
| `amb_rain_heavy` | amb_loop | 1 | loop | 7.70 | 22050 | Ambience | 100 | 20 |
| `amb_industrial` | amb_loop | 1 | loop | 10.00 | 16000 | Ambience | 100 | 20 |
| `amb_leaves` | amb_loop | 1 | loop | 8.60 | 16000 | Ambience | 100 | 20 |
| `amb_crickets` | amb_loop | 1 | loop | 7.65 | 16000 | Ambience | 100 | 20 |
| `amb_crowd` | amb_loop | 1 | loop | 11.50 | 16000 | Ambience | 100 | 20 |
| `amb_underwater` | amb_loop | 1 | loop | 7.60 | 11025 | Ambience | 100 | 20 |
| `amb_airport` | amb_loop | 1 | loop | 12.00 | 16000 | Ambience | 100 | 20 |

### Engine loops (EngineSound layers)

| id | category | variants | loop | length s | rate Hz | bus | range m | unit m |
|---|---|---|---|---|---|---|---|---|
| `eng_car_small_0` | amb_loop | 1 | loop | 0.99 | 16000 | Engine | 100 | 20 |
| `eng_car_small_1` | amb_loop | 1 | loop | 0.96 | 16000 | Engine | 100 | 20 |
| `eng_car_small_2` | amb_loop | 1 | loop | 0.97 | 16000 | Engine | 100 | 20 |
| `eng_car_small_3` | amb_loop | 1 | loop | 0.95 | 16000 | Engine | 100 | 20 |
| `eng_car_v6_0` | amb_loop | 1 | loop | 0.98 | 16000 | Engine | 100 | 20 |
| `eng_car_v6_1` | amb_loop | 1 | loop | 1.00 | 16000 | Engine | 100 | 20 |
| `eng_car_v6_2` | amb_loop | 1 | loop | 0.98 | 16000 | Engine | 100 | 20 |
| `eng_car_v6_3` | amb_loop | 1 | loop | 0.96 | 16000 | Engine | 100 | 20 |
| `eng_car_v8_0` | amb_loop | 1 | loop | 1.06 | 16000 | Engine | 100 | 20 |
| `eng_car_v8_1` | amb_loop | 1 | loop | 0.99 | 16000 | Engine | 100 | 20 |
| `eng_car_v8_2` | amb_loop | 1 | loop | 0.95 | 16000 | Engine | 100 | 20 |
| `eng_car_v8_3` | amb_loop | 1 | loop | 0.96 | 16000 | Engine | 100 | 20 |
| `eng_sports_0` | amb_loop | 1 | loop | 1.02 | 16000 | Engine | 100 | 20 |
| `eng_sports_1` | amb_loop | 1 | loop | 1.01 | 16000 | Engine | 100 | 20 |
| `eng_sports_2` | amb_loop | 1 | loop | 0.97 | 16000 | Engine | 100 | 20 |
| `eng_sports_3` | amb_loop | 1 | loop | 0.96 | 16000 | Engine | 100 | 20 |
| `eng_sports_whine` | amb_loop | 1 | loop | 1.00 | 16000 | Engine | 100 | 20 |
| `eng_truck_0` | amb_loop | 1 | loop | 0.95 | 16000 | Engine | 100 | 20 |
| `eng_truck_1` | amb_loop | 1 | loop | 0.95 | 16000 | Engine | 100 | 20 |
| `eng_truck_2` | amb_loop | 1 | loop | 0.97 | 16000 | Engine | 100 | 20 |
| `eng_truck_3` | amb_loop | 1 | loop | 0.98 | 16000 | Engine | 100 | 20 |
| `eng_truck_whine` | amb_loop | 1 | loop | 1.00 | 16000 | Engine | 100 | 20 |
| `eng_bike_0` | amb_loop | 1 | loop | 0.95 | 16000 | Engine | 100 | 20 |
| `eng_bike_1` | amb_loop | 1 | loop | 0.96 | 16000 | Engine | 100 | 20 |
| `eng_bike_2` | amb_loop | 1 | loop | 0.97 | 16000 | Engine | 100 | 20 |
| `eng_bike_3` | amb_loop | 1 | loop | 0.96 | 16000 | Engine | 100 | 20 |
| `eng_bike_whine` | amb_loop | 1 | loop | 1.00 | 16000 | Engine | 100 | 20 |
| `eng_boat_0` | amb_loop | 1 | loop | 0.95 | 16000 | Engine | 100 | 20 |
| `eng_boat_1` | amb_loop | 1 | loop | 0.97 | 16000 | Engine | 100 | 20 |
| `eng_boat_2` | amb_loop | 1 | loop | 0.95 | 16000 | Engine | 100 | 20 |
| `eng_heli_rotor_0` | amb_loop | 1 | loop | 1.14 | 16000 | Engine | 100 | 20 |
| `eng_heli_rotor_1` | amb_loop | 1 | loop | 0.96 | 16000 | Engine | 100 | 20 |
| `eng_heli_rotor_2` | amb_loop | 1 | loop | 1.05 | 16000 | Engine | 100 | 20 |
| `eng_heli_rotor_whine` | amb_loop | 1 | loop | 1.00 | 16000 | Engine | 100 | 20 |
| `eng_prop_plane_0` | amb_loop | 1 | loop | 0.95 | 16000 | Engine | 100 | 20 |
| `eng_prop_plane_1` | amb_loop | 1 | loop | 1.01 | 16000 | Engine | 100 | 20 |
| `eng_prop_plane_2` | amb_loop | 1 | loop | 0.95 | 16000 | Engine | 100 | 20 |
| `eng_jet_0` | amb_loop | 1 | loop | 1.00 | 16000 | Engine | 100 | 20 |
| `eng_jet_1` | amb_loop | 1 | loop | 1.00 | 16000 | Engine | 100 | 20 |
| `eng_jet_2` | amb_loop | 1 | loop | 1.00 | 16000 | Engine | 100 | 20 |
| `eng_jet_whine` | amb_loop | 1 | loop | 1.00 | 16000 | Engine | 100 | 20 |


## 7. Tunables
`Sfx.POOL_3D/POOL_2D` (voice pools), `Sfx.ALIASES`, `SoundBank.CATS` (per-category bus, range, unit size, polyphony, priority, pitch/volume variation, retrigger gap), per-id overrides in the `IDS` table of each
`bank_*.gd`, `EngineSound.NEAR_FULL`, `bank_engine.PROFILES` (idle/redline firing frequency, pulse pattern, resonances, noise, drive ...), `radio_music.STATIONS` (tempo, key, scale, progressions, swing),
`AudioSystem.DISTRICTS` (bed weights per district), `AudioSystem.safety_net`, `AudioSystem.auto_engine_sounds`, `RadioPlayer.OUTSIDE_RANGE`.

## 8. Known limits / honest notes
* Nothing was listened to (the authoring agent cannot hear): every sound was verified numerically (spectral centroid, decay time, pitch tracks, loop seams, RMS/peak, NaN/clipping, DC) and visually via spectrograms
  (`screenshots/audio_check/*.png`), so timbre and mix balance may need a human ear pass; loudness is tuned through the per-id `peak` values and the bus trims in `sfx.gd` (`BUSES`).
* Engine loops are pitch-shifted loops (not granular / physical synthesis in real time): fast rpm sweeps sound smooth but the exhaust resonances move with pitch.
* The radio renders at 22.05 kHz; the first phrase of a never-warmed station takes about 1-2 s (the tuning static covers it). Rendering speed 2-9x realtime per station.
* Doppler uses the engine's `AudioStreamPlayer3D` doppler (source velocity vs. static listener) and is only enabled beyond 14 m so the player's own car is not pitch-shifted.
* No interior detection exists in the world data: call `AudioSystem.set_space(&"interior")` etc. from the module that knows (garage, shops, tunnels).
* Voices are non-verbal synthesis (glottal source + formant filters): grunts, screams, coughs, breathing; no speech.
* `Sfx.play_3d` has one extra optional parameter (`follow`) and returns the player instead of `void`; both are compatible with the original stub contract.
