"""Persistent editor job server for the materials tooling (an UnrealEditor start costs 2-8 minutes on a loaded machine).

Start it ONCE (it keeps the project mutex while it runs, so no other Unreal process of this folder can start):
    powershell -NoProfile -ExecutionPolicy Bypass -File Tools/ue_cmd.ps1 -PythonScript Tools/ue/materials_server.py -LogName matserver -TimeoutSec 21600
Then submit jobs (any python script) with Tools/ue/materials_job.ps1:
    powershell -NoProfile -ExecutionPolicy Bypass -File Tools/ue/materials_job.ps1 Tools/ue/materials_build.py
Each job runs on the game thread inside a Slate post-tick callback (so it can freely use unreal.* editor APIs and block).
Log markers: MATJOB_START / MATJOB_DONE / MATJOB_EXC.  Stop the server by creating Saved/MatJobs/quit (or run a job calling QUIT_EDITOR).
"""
import glob
import os
import time
import traceback

import unreal

ROOT = unreal.Paths.project_dir().replace("\\", "/")
BASE = ROOT + "Saved/MatJobs"
INBOX = BASE + "/inbox"
OUTBOX = BASE + "/outbox"
for d in (INBOX, OUTBOX):
    os.makedirs(d, exist_ok=True)

STATE = {"idle_since": time.time(), "busy": False, "handle": None, "ticks": 0}
# -ExecutePythonScript quits the editor as soon as the script returned, unless this flag is set
unreal.EditorPythonScripting.set_keep_python_script_alive(True)


def _idle_limit():
    """Seconds without a job before the server exits (frees the project mutex for other agents). Override: Saved/MatJobs/idle_limit_s."""
    try:
        with open(BASE + "/idle_limit_s", "r") as fh:
            return float(fh.read().strip())
    except (OSError, ValueError):
        return 900.0


def _held():
    """True while an asynchronous multi-frame job (e.g. the test-sheet capture) wrote Saved/MatJobs/hold_<name> in the last 20 minutes:
    the server must not quit (quit flag / idle) before such work has finished."""
    now = time.time()
    for f in glob.glob(BASE + "/hold_*"):
        try:
            if now - os.path.getmtime(f) < 1200.0:
                return True
        except OSError:
            pass
    return False


def _run_one(path):
    base = os.path.basename(path)
    running = path + ".running"
    try:
        os.replace(path, running)
    except OSError:
        return
    unreal.log("MATJOB_START %s" % base)
    t0 = time.time()
    status = "OK"
    detail = ""
    ns = {}
    try:
        with open(running, "r", encoding="utf-8") as fh:
            src = fh.read()
        ns.update({"__name__": "__main__", "__file__": running.replace("\\", "/")})
        exec(compile(src, running, "exec"), ns)
    except BaseException:  # noqa: BLE001 - report everything, keep the server alive
        status = "EXC"
        detail = traceback.format_exc()
        unreal.log_error("MATJOB_EXC %s\n%s" % (base, detail))
    try:
        # NOTE: never clear ns - jobs register callbacks whose globals are ns (async sheets, log hooks)
        import gc
        gc.collect()  # collect Python wrappers of dead UObjects on the game thread (two editor crashes in python311.dll happened at GC time)
    except BaseException:  # noqa: BLE001
        pass
    dt = time.time() - t0
    unreal.log("MATJOB_DONE %s status=%s seconds=%.1f" % (base, status, dt))
    with open(OUTBOX + "/" + base + ".done", "w", encoding="utf-8") as fh:
        fh.write("%s\n%.1f\n%s\n" % (status, dt, detail))
    try:
        os.replace(running, running[:-len(".running")] + ".finished")
    except OSError:
        pass


def _tick(delta):
    STATE["ticks"] += 1
    if STATE["busy"]:
        return
    jobs = sorted(glob.glob(INBOX + "/*.py"))
    if jobs and not _held():  # an asynchronous capture in flight (hold_*) owns the editor world: queued jobs wait for it
        STATE["busy"] = True
        try:
            _run_one(jobs[0])
        finally:
            STATE["busy"] = False
            STATE["idle_since"] = time.time()
        return
    if _held():
        STATE["idle_since"] = time.time()
        return
    if os.path.exists(BASE + "/quit") or time.time() - STATE["idle_since"] > _idle_limit():
        try:
            os.remove(BASE + "/quit")
        except OSError:
            pass
        unreal.log("MATJOB_SERVER_QUIT")
        unreal.unregister_slate_post_tick_callback(STATE["handle"])
        unreal.EditorPythonScripting.set_keep_python_script_alive(False)
        unreal.SystemLibrary.execute_console_command(None, "QUIT_EDITOR")


STATE["handle"] = unreal.register_slate_post_tick_callback(_tick)
unreal.log("MATJOB_SERVER_READY inbox=%s" % INBOX)
