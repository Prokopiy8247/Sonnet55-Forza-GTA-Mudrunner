"""ONE COMMAND that builds / refreshes every world material of the project (idempotent, re-runnable).

Standalone (starts its own editor; ~2-10 min startup, then it quits):
    powershell -NoProfile -ExecutionPolicy Bypass -File Tools/ue_cmd.ps1 -PythonScript Tools/ue/materials_build.py -LogName materials_build
Through the persistent job server (Tools/ue/materials_server.py + materials_job.ps1), optional steps as the job argument:
    powershell -NoProfile -ExecutionPolicy Bypass -File Tools/ue/materials_job.ps1 Tools/ue/materials_build.py -Args0 "textures masters instances"

Steps (default = all, in this order):  mpc  textures  masters  instances  testsheet
  textures[=group,...]  import Content/Forza/Textures/Source/** -> /Game/Forza/Textures/<Group>/T_<name>_BC|N|ORM|D (force: add 'force')
  mpc                   /Game/Forza/Materials/MPC_Roam_World
  masters[=name,...]    the master materials M_Roam_*, M_Curb, ...   (Docs/Tech/MATERIALS.md)
  instances             MI_* for every Blender material slot name of the non-car kits (+ sensible extras)
  testsheet             builds /Game/Forza/Maps/L_MaterialTest (spheres/planes) and renders screenshots (job server only)
Log markers: MAT_BUILD / MAT_ERR / MAT_SUMMARY.
"""
import importlib
import os
import sys
import time
import traceback

import unreal

_ROOT = unreal.Paths.project_dir().replace("\\", "/")
_HERE = _ROOT + "Tools/ue"
if _HERE not in sys.path:
    sys.path.insert(0, _HERE)

_ARGS = globals().get("JOB_ARGS", "")  # injected by materials_job.ps1 (server mode)
_SERVER_MODE = "JOB_ARGS" in globals()


def _mods():
    """(re)load helper modules so edits are picked up by a long-running server."""
    names = ["materials_lib", "materials_textures", "materials_mpc", "materials_masters", "materials_instances", "materials_testmesh", "materials_testsheet"]
    out = {}
    for n in names:
        if not os.path.exists("%s/%s.py" % (_HERE, n)):
            continue
        if n in sys.modules:
            out[n] = importlib.reload(sys.modules[n])
        else:
            out[n] = importlib.import_module(n)
    return out


def main(args):
    toks = args.split() if args.strip() else ["mpc", "textures", "masters", "instances"]
    force = "force" in toks
    toks = [t for t in toks if t != "force"]
    M = _mods()
    L = M["materials_lib"]
    t0 = time.time()
    summary = []
    for tok in toks:
        name, _, opt = tok.partition("=")
        t1 = time.time()
        try:
            if name == "mpc":
                M["materials_mpc"].build()
            elif name == "textures":
                only = None
                if opt:
                    only = M["materials_textures"].sets_of_groups(opt.split(","))
                n = M["materials_textures"].import_all(force=force, only=only)
                summary.append("textures imported=%d" % n)
            elif name == "masters":
                res = M["materials_masters"].build_all(only=set(opt.split(",")) if opt else None)
                summary.append("masters %s" % res)
            elif name == "instances":
                res = M["materials_instances"].build_all()
                summary.append("instances %s" % res)
            elif name == "testsheet":
                import glob
                for f in sorted(glob.glob(_HERE + "/materials_testsheet_*.py")):  # station modules register themselves on import
                    mn = os.path.splitext(os.path.basename(f))[0]
                    importlib.reload(sys.modules[mn]) if mn in sys.modules else importlib.import_module(mn)
                M["materials_testsheet"].run(opt)
            else:
                L.warn("unknown step '%s'" % name)
        except Exception:  # noqa: BLE001
            unreal.log_error("MAT_ERR step=%s\n%s" % (name, traceback.format_exc()))
            summary.append("%s FAILED" % name)
        L.log("step %s done in %.1fs" % (name, time.time() - t1))
    unreal.log("MAT_SUMMARY %.1fs | %s" % (time.time() - t0, " | ".join(summary)))


main(_ARGS)
if not _SERVER_MODE:
    unreal.SystemLibrary.execute_console_command(None, "QUIT_EDITOR")
