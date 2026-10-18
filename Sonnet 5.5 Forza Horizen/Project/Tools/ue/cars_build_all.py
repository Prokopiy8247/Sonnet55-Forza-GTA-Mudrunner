"""One editor start for the whole vehicle pipeline (an editor start costs minutes): runs the stage scripts in order and quits.

    powershell -NoProfile -ExecutionPolicy Bypass -File Tools/ue_cmd.ps1 -PythonScript Tools/ue/cars_build_all.py -LogName cars_build_all -TimeoutSec 3600

Stages (environment variable ROAM_STAGES, default "materials,import,data"; showroom is separate: Tools/ue/cars_showroom.py):
    materials  Tools/ue/cars_materials.py   masters + MI_* instances (needed before the import binds slots)
    import     Tools/ue/cars_import.py      FBX import + material binding + validation table
    data       Tools/ue/cars_data.py        DA_Car_*, DA_CarCatalog, DA_TrafficVehicles
ROAM_ARGS ("only=car01,car02 skip_import=1") is forwarded to the stages as JOB_ARGS. Each stage runs in its own namespace and a failure
does not stop the next stage. Log marker: CARS_ALL.
"""
import os
import time
import traceback

import unreal

ROOT = unreal.Paths.project_dir().replace("\\", "/")
_OUTER_JOB = "JOB_ARGS" in globals()          # submitted to a persistent editor server: do not quit it
_JOB_OPTS = dict(tok.split("=", 1) for tok in str(globals().get("JOB_ARGS", "")).split() if "=" in tok)
STAGES = [s.strip() for s in _JOB_OPTS.get("stages", os.environ.get("ROAM_STAGES", "materials,import,data")).split(",") if s.strip()]
SCRIPTS = {"materials": "cars_materials.py", "import": "cars_import.py", "data": "cars_data.py", "showroom": "cars_showroom.py"}
ARGS = " ".join("%s=%s" % kv for kv in _JOB_OPTS.items() if kv[0] != "stages") or os.environ.get("ROAM_ARGS", "")

try:
    for stage in STAGES:
        path = ROOT + "Tools/ue/" + SCRIPTS[stage]
        unreal.log("CARS_ALL stage %s start (%s)" % (stage, path))
        t0 = time.time()
        ns = {"__name__": "__main__", "__file__": path, "JOB_ARGS": ARGS, "CARS_STANDALONE": not _OUTER_JOB}   # JOB_ARGS present = job mode: the stage must not quit the editor
        try:
            with open(path, "r", encoding="utf-8") as fh:
                exec(compile(fh.read(), path, "exec"), ns)
            unreal.log("CARS_ALL stage %s done in %.0f s" % (stage, time.time() - t0))
        except BaseException:  # noqa: BLE001
            traceback.print_exc()
            unreal.log_error("CARS_ALL stage %s FAILED" % stage)
finally:
    # the showroom stage is asynchronous (tick callback) and quits the editor itself when its queue is empty
    if not _OUTER_JOB and "showroom" not in STAGES:
        unreal.SystemLibrary.execute_console_command(None, "QUIT_EDITOR")
