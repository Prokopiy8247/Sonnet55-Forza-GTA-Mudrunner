"""Job entry point: render test-sheet stations (all materials_testsheet*.py station modules are imported first so they can register).

    powershell -NoProfile -ExecutionPolicy Bypass -File Tools/ue/materials_jobw.ps1 Tools/ue/materials_sheet.py -Args0 "trees,ground"
Screenshots: Saved/MatShots/<shot>.png (open with the Read tool).  The job returns immediately; the PNGs appear over the next minutes
(log markers MAT_SHEET_SHOT / MAT_SHEET_DONE).  While the capture runs this script holds the job server (Saved/MatJobs/hold_sheet) so a
pending quit request / idle timeout cannot kill the render half-way; the hold is released on MAT_SHEET_DONE / error (or expires after 20 min).
"""
import glob
import importlib
import os
import sys

import unreal

_ROOT = unreal.Paths.project_dir().replace("\\", "/")
_HERE = _ROOT + "Tools/ue"
if _HERE not in sys.path:
    sys.path.insert(0, _HERE)

for _mod in ("materials_lib", "materials_textures", "materials_testmesh", "materials_testsheet"):
    importlib.reload(importlib.import_module(_mod)) if _mod in sys.modules else importlib.import_module(_mod)
import materials_testsheet as TS  # noqa: E402

for _f in sorted(glob.glob(_HERE + "/materials_testsheet_*.py")):
    _n = os.path.splitext(os.path.basename(_f))[0]
    importlib.reload(sys.modules[_n]) if _n in sys.modules else importlib.import_module(_n)

_HOLD = _ROOT + "Saved/MatJobs/hold_sheet"
os.makedirs(os.path.dirname(_HOLD), exist_ok=True)
with open(_HOLD, "w") as _fh:
    _fh.write("sheet running")

_orig = {"log": unreal.log, "err": unreal.log_error}


def _release():
    try:
        os.remove(_HOLD)
    except OSError:
        pass
    unreal.log = _orig["log"]
    unreal.log_error = _orig["err"]


def _log(msg, *a, **k):
    _orig["log"](msg, *a, **k)
    if "MAT_SHEET_DONE" in str(msg):
        _release()


def _log_error(msg, *a, **k):
    _orig["err"](msg, *a, **k)
    if "MAT_ERR sheet" in str(msg):
        _release()


unreal.log = _log
unreal.log_error = _log_error
try:
    TS.run(globals().get("JOB_ARGS", "").strip())
except Exception:  # noqa: BLE001
    _release()
    raise
