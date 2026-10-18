"""lane13_run.py - usage inside Blender (MCP):  LANE13_SCRIPT = 'lane13_train_car.py'; exec(open(r'<this file>').read(), globals())
Loads gta_lib + lane13_lib (+ lane13_traincommon when the script name starts with lane13_train) and executes the builder script."""
import os
_T = r"W:\YouTube\Claude Sonnet 5.5\GTA\godot-sonnet-5.5gta\tools\blender"
if "MB" not in globals():
    exec(open(os.path.join(_T, "gta_lib.py"), encoding="utf8").read(), globals()); assert_master()
exec(open(os.path.join(_T, "lane13_lib.py"), encoding="utf8").read(), globals())
if LANE13_SCRIPT.startswith("lane13_train"):
    exec(open(os.path.join(_T, "lane13_traincommon.py"), encoding="utf8").read(), globals())
exec(open(os.path.join(_T, LANE13_SCRIPT), encoding="utf8").read(), globals())
