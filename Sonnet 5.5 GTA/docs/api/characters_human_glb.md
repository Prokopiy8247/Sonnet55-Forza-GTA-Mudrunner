# characters/human.glb  (Blender lane 4 - Characters)

`res://gta/generated/models/characters/human.glb` - ONE file with the shared skeleton and every skinned human body / accessory mesh.
Built by `tools/blender/lane4_*.py` (re-runnable; source objects live in the master .blend, collection `GTA_GODOT/Characters`, prefix `human__`).

## Import result (verified with `gta/tests/human_glb_probe.gd`)
```
human (Node3D, file root)
  Armature (Node3D)
    HandSocket_R / HandSocket_L (Node3D, plain empties - NOT parented to bones)
    Skeleton3D (Skeleton3D)          <- Godot names it "Skeleton3D" (not "Skeleton"): find it by class / find_child("Skeleton3D", true, false)
      Body_A  Body_B  Body_C  Hair_1..Hair_6  Beard_1  Beard_2  Hat_Cap  Hat_Beanie  Hat_Police  Helmet_Tactical
      Glasses_Round  Glasses_Shades  Vest_Armor  Vest_Tactical  Jacket_Short  Jacket_Long  Backpack      (all MeshInstance3D, all skinned)
```
* Character is 1.80 m, origin between the feet, rest pose = relaxed A-pose, front = -Z, `_R` = +X side (matches ARCHITECTURE s12).
* **Bones: 21, not 22.** The s12 table lists 5 centre bones (Hips Spine Chest Neck Head) + 8 per side (Shoulder UpperArm LowerArm Hand UpperLeg LowerLeg Foot Toe) = 21. The table was followed EXACTLY (names, parents, head/tail); no helper bone was invented to reach "22".
* Bone order in Godot: Hips Spine Chest Neck Head Shoulder_L UpperArm_L LowerArm_L Hand_L Shoulder_R ... UpperLeg_L ... Toe_R (look up by name, never by index).
* No animations are exported (procedural animation by the Rig agent).

## Meshes (triangles after export) and materials
| mesh | tris | material slots |
|---|---|---|
| Body_A (average masculine) / Body_B (average feminine, narrow waist, bust, wider hips) / Body_C (stocky: broader chest, belly, thicker limbs) | ~2040 / ~2020 / ~2040 (budget 4500) | `Skin` `Shirt` `Pants` `Shoes` `Accent` + `Trim` (eyes, mouth, shoe sole) + `Chrome` (belt buckle) |
| Hair_1 crop, Hair_2 side part, Hair_3 long straight, Hair_4 ponytail (+Accent tie), Hair_5 curly afro, Hair_6 mohawk | 106-182 | `Hair` (Hair_4 also `Accent`) |
| Beard_1 full + moustache, Beard_2 goatee | 60 / 36 | `Hair` |
| Hat_Cap (crown Accent, brim Trim), Hat_Beanie (Accent + Trim cuff), Hat_Police (Accent/Trim, `Chrome` badge), Helmet_Tactical (`Gun` + `Trim`, visor `Glass`) | 146 / 202 / 138 / 194 | see left |
| Glasses_Round, Glasses_Shades | 212 / 120 | `Trim` + `Glass` |
| Vest_Armor (slim), Vest_Tactical (bulky, pouches) | 208 / 384 | `Trim` `Accent` |
| Jacket_Short, Jacket_Long (sleeves + collar) | 340 / 376 | `Shirt` (body/sleeves) `Accent` (hem, cuffs, collar, placket) |
| Backpack | 188 | `Accent` `Trim` |

Recolour by material NAME (`Util.replace_material`): Skin, Hair, Shirt, Pants, Shoes, Accent. `Trim`, `Chrome`, `Gun`, `Glass` are fixed props. Every Body has an eyes/mouth `Trim` surface, so do NOT tint `Trim` with the shoe colour.

## Fit rules
* Head: the cranium (z >= 1.66 m) is identical on A/B/C, so every Hair/Hat/Helmet/Glasses/Beard fits all three bodies. Hair + hats overlap (a hat shell is 1.0-1.5 cm larger than a hair shell): hide the hair when a hat/helmet is worn unless you want a mohawk/ponytail sticking out.
* Torso accessories (vests, jackets, backpack) are built to the max envelope of A/B/C (+1.2 cm vest, +2.2 cm jacket): snug on Body_C, loose/puffy on Body_B.
* Accessories are skinned to the SAME skeleton: hats/hair/glasses/beards 100% `Head`; backpack 100% `Chest`; vests/jackets use the same smooth weights as the body (spine chain, shoulders, elbows); Jacket_Long hem blends Hips -> UpperLeg by |x| so the coat follows leg swings.
* Skin weights are soft at every joint (blend 0.06-0.15 m); verified in Blender with pose tests: UpperArm 80 deg + LowerArm 90 deg, UpperLeg 70 deg + LowerLeg -90 deg, Spine -25 deg, Head 40 deg yaw (and sit / walk / aim / arms-up poses) on Body_A/B/C and the accessories - no pinched elbows, no knee tearing, no shoulder collapse.

## Hand sockets
`HandSocket_R` at model-space (0.43, 0.04, 0.78) Blender = Godot (0.43, 0.78, -0.04); `_L` mirrored. Identity rotation: a weapon exported with barrel +Y (Blender) = -Z (Godot) placed with identity transform points along the character's facing. The Rig agent should re-parent weapons to a `BoneAttachment3D` on `Hand_R`/`Hand_L` and use the socket position (in rest pose) as the offset from the bone.

## Rebuild
In Blender (port 9890) after `gta_lib.py`: `exec(open(PROJECT+r"\tools\blender\lane4_build_all.py").read(), globals())` rebuilds every mesh (rig kept), then `lane4_export.py` exports, then `tools\gd.ps1 import` + `script res://gta/tests/human_glb_probe.gd`. Add `C4_REBUILD_RIG = True` before the exec to recreate the rig (deletes all human__ meshes first).
Files: `lane4_lib.py` (skeleton, part-tag skin weighting), `lane4_rig.py`, `lane4_body.py`, `lane4_head.py`, `lane4_hair.py`, `lane4_hats.py`, `lane4_gear.py`, `lane4_pose.py` (pose test on copies), `lane4_preview.py` (variety rows), `lane4_export.py`.

## Known limits
* Faces are flat/simple (eyes + mouth are dark insets, no eyebrows, no teeth); hands are mitten + thumb (no separate fingers).
* Hair under hats clips if both are visible; Jacket on Body_B is boxy (shared shell).
* Only ONE Skeleton3D (`Skeleton3D`) - not renamed to "Skeleton" because Godot's glTF importer picks the node name.

## Verification done
* Blender: pose tests on COPIES of the rig (walk, sit, aim, arms-up, deep crouch 100/130 deg, spine/head twist) on Body_A/B/C with hair/hats/vests/jackets/backpack - clean deformation (images in conversation; `lane4_pose.py`).
* Godot: `gta/tests/human_glb_probe.gd` -> `HUMAN RESULT PASS` (21 bones with the exact names, 22 meshes all skinned with bone indices + weights, every tri budget, HandSocket empties).
* Godot (real renderer): `gta/tests/human_preview.gd` builds a 6-character recoloured lineup + one figure posed through the Skeleton3D API (`tools\gd.ps1 shot -Out screenshots\human_godot.png -GameArgs "--exec=res://gta/tests/human_preview.gd --delay=5 --time=14"`). `--hp=legs|arms|spine|head` poses a single figure only.
* Blender variety previews: `screenshots/human_preview_bodyA.png`, `..._bodyB.png`, `..._bodyC.png` (4 recoloured variants each).

## Notes for the Rig agent
* Godot 4 bone poses are ABSOLUTE local transforms (not offsets from rest). To rotate a bone by a model-space delta use `local = parent_rest_global.basis.inverse() * R * parent_rest_global.basis * bone_rest.basis` (what `human_preview.gd::_pose` does) or `Util.bone_set_model_delta`.
* Rest orientation of the bones follows the Blender bone axes (slight tilts on arm/leg bones, e.g. `UpperLeg_R` rest basis x = (0.999, 0.024, 0.024)); never assume identity rest bases.
* Meshes are NOT parented under bones: each `MeshInstance3D` under `Skeleton3D` carries a `Skin`; show/hide meshes by name and apply `Util.replace_material` for Skin/Hair/Shirt/Pants/Shoes/Accent.
