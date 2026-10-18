# Blender weapon assets (lane 5) - `res://gta/generated/models/weapons/*.glb`

Authored in Blender (`GTA_GODOT/Weapons`), source objects live in `GodotSonnet5.5GTA.blend`, rebuilt by `tools/blender/weapons_*.py`
(`weapons_common.py` = helpers; one builder script per asset, all idempotent: they start with `clear_asset("<id>__")`).

## Contract (as exported)
* Real-world scale in metres. **Origin = primary grip (palm)**, barrel toward **-Z in Godot** (+Y in Blender), up = +Y.
* Every GLB root has the exact node names below (the `<id>__` Blender prefix is stripped on export).
* Parts are separate meshes, all with their origin at the weapon origin (so a pure translation animates them) except `Cylinder`
  (revolver / grenade launcher) whose origin is on the cylinder axis (spin it around its local **Z** axis in Godot = Blender Y).
* Empties: `Muzzle` (barrel tip), `Grip_L` (support hand), `Eject` (case ejection port, right side), mounts `AttMuzzle`, `AttOptic`, `AttRail`,
  `AttGrip`, `AttMag` (attachment GLBs are parented there with identity transform). `AttMag` carries a small rotation on raked grips
  (pistol -12 deg, assault rifle +10 deg about X), so the extended magazine follows the grip axis.
* Materials (named, swap by name): `Gun` and `GunLight` = the finish that `WeaponModel.set_tint` recolours; `Grip`, `Wood`, `WoodDark`,
  `Metal`, `MetalDark`, `Trim` (black), accent colours `GunAccent` (orange), `GunRed`, `SightDot` (emissive green dot), `ScopeLens` (emissive blue),
  `LampGlow` (flashlight lens, emissive), `GunOlive` / `GunTan` (olive / desert polymer furniture), `GrenadeBody`.

## Assets
| id | length (m) | tris | parts (mesh nodes) | anchors |
|---|---|---|---|---|
| pistol | 0.21 | 800 | Body, Slide, Magazine, Trigger | Muzzle Grip_L Eject AttMuzzle AttOptic AttRail AttGrip AttMag |
| smg | 0.45 | 1172 | Body, Bolt, Magazine, Trigger | same set |
| rifle_assault | 0.95 | 1140 | Body, Bolt, Magazine, Trigger | same set |
| shotgun_pump | 1.02 | 860 | Body, Pump, Trigger | Muzzle Grip_L Eject AttMuzzle AttOptic AttRail AttGrip (no AttMag: tube magazine) |
| sniper | 1.31 | 1152 | Body, Scope (integrated 6x), Bolt, Magazine, Bipod (folded), Trigger | full set |
| revolver | 0.26 | 788 | Body, Cylinder, Hammer, Trigger | Muzzle Grip_L Eject AttMuzzle AttOptic AttRail AttGrip |
| carbine | 0.82 | 800 | Body, Bolt, Magazine, Trigger | full set |
| rifle_marksman | 1.10 | 800 | Body, Bolt, Magazine, Trigger | full set |
| shotgun_auto | 0.95 | 792 | Body, Bolt, Magazine (drum), Trigger | full set (AttMag = bottom of the drum) |
| rocket_launcher | 1.05 | 800 | Body, Rocket (visible warhead, hide when empty), Trigger | Muzzle Grip_L Backblast AttOptic AttMuzzle |
| grenade_launcher | 0.81 | 764 | Body, Cylinder (6-chamber drum), Trigger | Muzzle Grip_L Eject AttOptic AttMuzzle AttRail |
| knife | 0.26 | 380 | Body | Muzzle (=blade tip) Tip Grip_L |
| bat | 0.85 | 448 | Body | Muzzle (=tip) Tip Grip_L |
| crowbar | 0.65 | 232 | Body | Muzzle (=claw) Tip Grip_L |
| grenade | 0.10 tall (fuze up +Y in Godot, origin = body centre) | 424 | Body (egg + spoon + pin + ring) | Muzzle Grip_L |
| att_suppressor | 0.20 | 352 | Body | Muzzle (tip) |
| att_scope | 0.28 | 404 | Body (emissive `ScopeLens` at both ends) | Eye (rear lens), Muzzle (front lens) |
| att_flashlight | 0.12 | 332 | Body (emissive `LampGlow` lens) | LightPoint (lens centre, for the SpotLight) |
| att_grip | 0.12 tall | 276 | Body | - |
| att_magazine_ext | 0.14 | 208 | Body | - |

Attachment origins = their mount point, +Y (Blender) forward: suppressor starts at the muzzle and points forward; scope sits on the optic mount
(origin = rail contact, tube axis 4 cm above); flashlight and vertical grip hang BELOW the rail contact; the extended magazine hangs below the mag
top (origin = feed lips) and is deliberately fatter than the standard magazines so it fully covers the standard `Magazine` mesh when mounted.

## Notes for integrators
* Hide / free the standard `Magazine` node when `att_magazine_ext` is mounted (the extended mag replaces it; it is 4 cm longer than the
  standard pistol / SMG / rifle magazines and covers them, but the shotgun_auto drum stays visible).
* `Slide`, `Bolt`, `Pump` slide along the barrel axis, `Magazine` drops along the grip axis; no pivots are required.
* The `Rocket` mesh of the rocket launcher is the loaded warhead; `Backblast` is the venturi anchor (no `Eject` on purpose).
* Triangle counts above are the Blender counts of the exported meshes (checked equal to the Godot import). Every primitive is its own closed,
  outward-facing shell (verified: all shell volumes positive, zero non-manifold edges); details overlap the surface they sit on, there are no
  coplanar duplicate faces. `Gun`/`GunLight` carry the finish colour (tint), the rest of the palette is untouched by `set_tint`.
* Visual QA scene: `tools\gd.ps1 shot -Out screenshots\wpn.png -GameArgs "--exec=res://gta/tests/blender5_weapons_showcase.gd --delay=3 --time=12"`
  (env `WPN_SHOW`, `WPN_ATT`, `WPN_CAM`, `WPN_COLS`, `WPN_YAW`; mounts attachments on the weapons' `Att*` empties when `WPN_ATT` is set).
