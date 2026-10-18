"""world_matcheck - recompiles every master Material under /Game/Forza and reports compile errors (marker ROAM_MATCHECK).

Finds the 'CollectionParameter has invalid parameter None' breakage (MPC_Roam_World parameter GUIDs changed after a master was compiled):
such a material renders as the engine checkerboard in the game.  Read-only apart from the recompile.
Run as a job:  powershell -NoProfile -ExecutionPolicy Bypass -File Tools/ue/ue_job.ps1 Tools/ue/world_matcheck.py -TimeoutSec 1800 -Args0 "root=/Game/Forza"
JOB_ARGS "fix=1" additionally saves the materials that compiled cleanly after the recompile (they were rebuilt in place).
"""
import time

import unreal

ARGS = globals().get("JOB_ARGS", "") or ""
ROOT = "/Game/Forza"
for tok in ARGS.split():
    if tok.startswith("root="):
        ROOT = tok.split("=", 1)[1]


def main():
    t0 = time.time()
    ar = unreal.AssetRegistryHelpers.get_asset_registry()
    mel = unreal.MaterialEditingLibrary
    bad = 0
    total = 0
    for a in ar.get_assets_by_path(ROOT, recursive=True):
        if str(a.asset_class_path.asset_name) != "Material":
            continue
        path = str(a.package_name)
        mat = unreal.EditorAssetLibrary.load_asset(path)
        if mat is None:
            continue
        total += 1
        t1 = time.time()
        try:
            errs = [str(e) for e in mel.recompile_material(mat)]
        except Exception as exc:  # noqa: BLE001
            errs = ["EXC %r" % (exc,)]
        if errs:
            bad += 1
        unreal.log("ROAM_MATCHECK %s errors=%d %.1fs %s" % (path, len(errs), time.time() - t1, [e[:160] for e in errs[:2]]))
    unreal.log("ROAM_MATCHECK_SUMMARY materials=%d with_errors=%d %.1fs" % (total, bad, time.time() - t0))


main()
