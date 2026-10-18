# CharacterRig - visual + procedural animation of every humanoid (Rig agent)

Files (all under `gta/code/player/`): `character_rig.gd` (node), `character_variants.gd` (appearance generators),
`rig_motion.gd` (animation brain), `rig_solver.gd` (IK / bone writer), `rig_pose.gd` (pose channels), `ragdoll_body.gd`
(physics ragdoll), `rig_fallback.gd` (procedural stand-in model, only used while `characters/human.glb` is missing).
Tests: `gta/tests/rig_test.gd` (+ `rig_runner.gd`, standalone), `gta/tests/rig_sheet.gd` (contact sheets), `rig_ragdoll_debug.gd`.

Everything is pure code on the `Skeleton3D` of `characters/human.glb` (skeleton per ARCHITECTURE s12, **bone roll independent**:
only rest positions are used). No AnimationPlayer, no animation resources. Cost: ~0.12 ms per rig update at full rate
(measured: 60 rigs = 115-170 us each in GDScript), 0 when `lod = 2`.

## Quick start (owner = CharacterBase subclass)
```gdscript
var rig := CharacterRig.new()
add_child(rig)                                   # origin = between the feet, faces -Z
rig.setup(CharacterVariants.random_pedestrian(rng))   # or player_default() / police_officer() ...
self.rig = rig
# every frame (physics or process):
rig.set_locomotion(speed, local_move_dir, sprinting)   # local_move_dir: x right, z back, forward = (0,0,-1)
rig.set_aim(is_aiming, pitch_rad, yaw_offset_rad)
rig.set_weapon_pose(weapon_def.pose)                   # &"pistol" &"smg" ... straight from WeaponDefs "pose"
rig.set_stance(&"crouch")
```
The rig animates itself in `_process`. It estimates the owner's velocity from its own movement (used by the ragdoll).
`setup()` may be called again at any time (re-dress); whatever is mounted in the hand sockets survives.

## Variant dictionary (`setup`, `CharacterVariants.*`)
| key | type | meaning |
|---|---|---|
| `body` | `&"A"` `&"B"` `&"C"` | A average masculine, B feminine, C stocky (missing Body_x mesh -> Body_A, logged once) |
| `skin`, `shirt`, `pants`, `shoes`, `accent` | Color | replace the material slots Skin/Shirt/Pants/Shoes/Accent |
| `hair` | int 0..6 | hair style (0 bald); `hair_color` Color (a Color in `hair` is also accepted as the colour) |
| `hat` | `""` `&"Hat_Cap"` `&"Hat_Beanie"` `&"Hat_Police"` `&"Helmet_Tactical"` | suffix form (`&"Cap"`) also accepted |
| `glasses` | `&"Glasses_Round"` `&"Glasses_Shades"` | |
| `jacket` | `&"Jacket_Short"` `&"Jacket_Long"` | colour = `jacket_color` (default: darker shirt) |
| `vest` | `&"Vest_Armor"` `&"Vest_Tactical"` | colour = `vest_color` |
| `backpack` | `&"Backpack"` | colour = `pack_color` |
| `beard` | `&"Beard_1"` `&"Beard_2"` | uses `hair_color` |
| `hat_color` | Color | Accent surfaces of hats / helmets |
| `scale` | float 0.92..1.08 | whole-rig scale (hand sockets are counter-scaled, weapons keep real size) |
| `kind` | StringName | informational (`pedestrian police tactical shop gang player`) |

Materials are flat `StandardMaterial3D` (roughness 0.85) applied as per-surface overrides by **material name**; they are shared per
(slot, colour), so 60 pedestrians do not create hundreds of materials. Unused variant meshes are freed at `setup()`.

`CharacterVariants`: `random_pedestrian(rng)`, `police_officer(rng)`, `tactical_officer(rng)`, `shop_staff(rng)`, `gang_member(rng)`,
`player_default()` (teal bomber jacket, white tee, navy jeans, white sneakers with magenta trim, swept dark hair, stubble),
`make(kind, rng)`, `appearance_name(variant) -> String` (e.g. "police officer, police blue shirt, armor vest, charcoal trousers, police cap").
`rng` may be null (own generator). Colour palettes are `const`s on the class (Halcyon palette).

## Public API (`CharacterRig`)
Required contract (ARCHITECTURE s8): `setup(variant)`, `set_locomotion(speed, move_dir_local, sprinting)`, `set_stance(stance)`,
`set_aim(active, pitch, yaw_offset)`, `set_weapon_pose(kind)`, `play_action(action)`, `get_hand_socket(right := true) -> Node3D`,
`get_skeleton() -> Skeleton3D`, `get_head_position() -> Vector3`, `start_ragdoll(impulse, hit_position)`, `stop_ragdoll()`,
`look_at_point(p)`.

* **stance**: `stand crouch cover_low cover_high swim_surface swim_under sit_car sit_bike ladder parachute ragdoll dead`.
  `ragdoll` calls `start_ragdoll()`; leaving it calls `stop_ragdoll()`. `dead` = lying pose (face up or down), cheap alternative to a ragdoll.
* **weapon pose**: `none pistol smg rifle shotgun sniper heavy melee_knife melee_bat thrown` (= `WeaponDefs "pose"`). The weapon
  scene must be parented to `get_hand_socket(true)` with its origin at the grip and the barrel along -Z (ARCHITECTURE s7); the rig
  finds a `Grip_L` node inside it and puts the left palm exactly on it for two-handed weapons (`refresh_weapon_grip()` is called
  automatically a few frames after `set_weapon_pose`; call it manually after swapping weapon models without changing the pose kind).
* **play_action(action, duration := -1.0)**: `punch kick melee_swing reload hit_react jump land enter_vehicle exit_vehicle throw hands_up`
  plus `hands_down` (releases hands_up) and `stop`. `duration` overrides the default length: punch .42, kick .62, melee_swing bat .62 /
  knife .48, reload 1.7 (pass the weapon's reload_time!), throw .75, enter .55, exit .5. `punch` alternates hands, `melee_swing`
  follows the current weapon pose (bat arc / knife stab / fists). `jump` starts the airborne pose until `land` (or `set_grounded(true)`).
  `hands_up` is held until `hands_down` (or a stance change away from stand / crouch, or `rig.motion.hands_up_hold` = 25 s;
  call `play_action(&"hands_up")` again to renew). `hit_react` through `play_action` flinches in a random "pushed back" direction,
  `hit_react(world_direction)` flinches along the real hit direction. A `jump` that nobody reports as a fall (`set_grounded(false, vy)`)
  lands by itself after 1.4 s.
* Extra control (all optional, additive): `stop_action()`, `is_action_playing(action := &"")`, `action_progress()`,
  `hit_react(world_direction, strength := 1.0)` (flinch pushed along the hit direction), `set_grounded(grounded, vertical_velocity)`
  (falling / landing dip), `set_steering(-1..1)` (wheel / handlebar / parachute line), `set_lean(roll)` (bike body lean),
  `set_cover_peek(-1..1)`, `set_seat(role := &"driver"|&"passenger", offset := Vector3.ZERO)`, `set_ride_style(&"motorcycle"|&"bicycle")`
  (bicycle = pedalling feet from locomotion speed), `set_idle_style(&"relaxed"|&"arms_crossed"|&"hands_pockets"|&"phone")`,
  `set_first_person(bool)` (hides head / hair / hat meshes and shrinks the head bone), `clear_look()`, `get_eye_position()`,
  `get_ragdoll_position()`, `is_ragdoll()`, `is_ragdoll_frozen()`, `is_built()`, `refresh_weapon_grip()`.
* **look_at_point(p)**: the head / neck / chest track a world point (limits +-77 deg yaw, +-40 deg pitch) for ~0.7 s after the last call.
* Locomotion: `speed` in m/s decides walk / jog / run / sprint (blends continuously, thresholds ~1.4 walk, ~3 jog, ~4.5 run, 7+ sprint);
  `move_dir_local` supports strafing and walking backwards (the body keeps facing forward, the legs step in the movement direction).
  In water / on ladders `move_dir_local.y` and the sign of `z` give vertical movement. Planted feet do not slide (stance foot speed ==
  `speed`; verified by `rig_no_slide_*` tests). Turning of the owner (yaw rate of the rig node) leans the body automatically.

### Seat contract (vehicles)
In `sit_car` / `sit_bike` the **rig origin must be the seat point** (the vehicle's `SeatDriver` empty): the pelvis rests ~0.08 m above it,
thighs forward, shins down to the pedals, hands on the wheel / bars. Use `set_seat(role, offset)` for per-vehicle tuning (offset in
metres, rig space). The vehicle (or the player) should rotate the rig node with the seat. Steering input -> `set_steering()`.
In `swim_*` the rig origin is the water surface point above the body centre; `parachute`: origin = feet (legs hang below the hips).

### Ragdoll
`start_ragdoll(impulse, hit_position)`: `impulse` is a **velocity change in m/s** applied to the whole body (about 3-10 for a strong hit,
clamped at 25), concentrated on the bone nearest `hit_position` (world). The rig's own movement is inherited. `PhysicalBoneSimulator3D`
+ 14 `PhysicalBone3D` bodies (hips, spine, chest, head, upper/lower arms, upper/lower legs, feet) with cone-twist + hinge joints, layer
`GC.L_RAGDOLL`, mask `world | vehicle | prop`, no self collision. After ~8 s or as soon as the body is calm (< 0.14 m/s for 0.9 s) it is
**frozen**: the final pose is baked into the skeleton and every physics object is freed; signal `ragdoll_settled` is emitted.
At most `RagdollBody.MAX_LIVE = 8` ragdolls are alive (static list): starting a 9th freezes the oldest early (it also emits
`ragdoll_settled`). `stop_ragdoll()` blends from the ragdoll pose to the animated pose over 0.5 s - **teleport the owner to
`rig.get_ragdoll_position()` first** so the get-up happens where the body lies. While ragdolling the mesh follows the physics bodies in
world space regardless of where the owner node is; `get_head_position()` follows the head body.
Signals: `ragdoll_started`, `ragdoll_settled`.

### Seat / vehicle notes (matches `VehicleBase.SIT_HIP_DROP = 0.085`)
The seat empties are pelvis points; the vehicle places the rig origin 0.085 m below them. The rig's hips joint then sits 0.085 m above its
origin, so thighs are horizontal on the cushion. Hands follow the wheel (driver) or rest on the thighs (passenger), `set_steering` turns
the hands up to ~110 degrees around the wheel centre (0.45 m ahead, 0.30 m above the seat point, 0.18 m radius).

### LOD / performance
`rig.lod`: 0 full rate, 1 about 15 Hz, 2 frozen (no animation, no cost). `auto_lod` (default true) picks the level itself every ~0.3-0.5 s
from the camera distance (< 38 m full, < 75 m reduced, beyond / off-screen frozen). Owners that want to drive it themselves set
`rig.auto_lod = false` and write `rig.lod`. Idle characters (standing / crouching still, no action, not aiming, no look-at) update at 30 Hz automatically.
Tests / cutscenes can set `rig.manual_update = true` and call `update_pose(dt)`.

### Tunables
`RigMotion` constants: `GAIT_V/F/D/LIFT/ARM` (speed -> cadence, stance fraction, foot lift, arm swing), `HOLD` (weapon grip table per pose kind:
carry position/direction and aim offsets), `MODE_TIME` (blend times of the pose modes). `RagdollBody`: `MAX_LIVE`, `FREEZE_AFTER`, `CALM_SPEED`,
`CALM_TIME`, `DEFS` (mass / shape / joint limits per bone). `CharacterRig`: `LOD_NEAR`, `LOD_MID`.

## Verification
`gta/tests/rig_test.gd` (32 checks, all PASS; run `tools\gd.ps1 exec -Script res://gta/tests/rig_test.gd` or standalone
`tools\gd.ps1 script -Script res://gta/tests/rig_runner.gd`): variants build / diversity / names, every stance and action finite and sane,
no foot sliding at 1.4 / 2.4 / 4.5 / 7 m/s, hand socket attached and pointing along the arm, weapon barrel forward, left hand on `Grip_L`,
re-dress keeps weapons, turn lean, hands-up timeout, first person, jump auto-landing, ladder direction, LOD (manual + camera distance),
60-rig update cost (~0.1-0.2 ms each), no pops during state switches, ragdoll (falls, settles, bones keep their lengths, impulse moves the
body, get-up, live cap 8). `gta/tests/rig_sheet.gd` renders the contact sheets in `screenshots/rig/` (variants, walk / run / sprint cycles,
aim with every weapon pose + pitch, carry, stances, actions, closeups, pistol closeups, ragdoll sequence, action timelines):
`tools\gd.ps1 shot -Out screenshots\rig\final.png -GameArgs "--exec=res://gta/tests/rig_sheet.gd --delay=2"` (env `RIG_SHEETS=aim,ragdoll` selects sheets).

## Known limits
* Skeleton must follow ARCHITECTURE s12 (21 deform bones named Hips ... Toe_L); otherwise the rig logs an error and stays in the rest pose.
* Feet are planted on a flat ground at the rig origin height (no terrain-slope foot IK).
* `sit_*` poses assume the seat point contract above; very tall / low vehicles may need `set_seat(offset)`.
* A rig scaled by `scale` != 1 passes the scale to its physics bodies (Jolt accepts the small uniform scale; shapes are not rescaled).
* The skeleton's own bone poses (`get_bone_global_pose`) are only updated by the engine at render time while a ragdoll simulates; use
  `get_head_position()` / `get_ragdoll_position()` / `RagdollBody.part_position(slot)` instead of reading bones during a ragdoll.
* PhysicalBone3D joint properties are in degrees (cone `swing_span`, `twist_span`, hinge `angular_limit_*`), see `RagdollBody._setup_joint`.
* Re-calling `setup()` re-creates the Skeleton3D: re-fetch `get_skeleton()` afterwards.
