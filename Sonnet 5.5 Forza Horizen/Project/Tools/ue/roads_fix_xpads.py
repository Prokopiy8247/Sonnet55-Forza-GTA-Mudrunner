"""Editor job: the 'RJ_X_*' junction pads (draped fans where two roads cross) have up to ~1 m steps against the neighbouring road chunks
(found by the autopilot loop test: LOOP_COAST s~675 stops cars). The terrain under them is carved to the road bed (<= 0.2 m), so the
pads are made VISUAL ONLY (no collision) and wheels/cars drive on the carved landscape instead.
Run: powershell -NoProfile -ExecutionPolicy Bypass -File Tools/ue/ue_job.ps1 Tools/ue/roads_fix_xpads.py   (then save: this script saves the level)"""
import unreal

EAS = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)
LES = unreal.get_editor_subsystem(unreal.LevelEditorSubsystem)
world = unreal.EditorLevelLibrary.get_editor_world() if hasattr(unreal.EditorLevelLibrary, "get_editor_world") else None
changed = 0
names = []
for a in EAS.get_all_level_actors():
    lbl = a.get_actor_label()
    if not lbl.startswith("Road_RJ_X_"):
        continue
    comps = a.get_components_by_class(unreal.StaticMeshComponent)
    for c in comps:
        c.set_collision_enabled(unreal.CollisionEnabled.NO_COLLISION)
        changed += 1
    names.append(lbl)
unreal.log("XPADS_FIX components=%d actors=%d %s" % (changed, len(names), names))
if changed:
    LES.save_current_level()
    unreal.log("XPADS_FIX level saved")
