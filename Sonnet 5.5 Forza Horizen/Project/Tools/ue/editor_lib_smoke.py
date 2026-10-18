"""Proves that the editor-only module Sonnet55ForzaEditor loaded and that URoamEditorLibrary is callable from Python.

Run:  powershell -File Tools/ue_cmd.ps1 -PythonScript Tools/ue/editor_lib_smoke.py -LogName editor_lib_smoke
Expected log lines (grep ROAM_EDITOR_LIB_SMOKE):
    ROAM_EDITOR_LIB_SMOKE status=RoamEditorLibrary OK (UE 5.8.2)
    ROAM_EDITOR_LIB_SMOKE add=42
    ROAM_EDITOR_LIB_SMOKE result=PASS
"""
import unreal

ok = True
try:
    status = unreal.RoamEditorLibrary.get_roam_editor_library_status()
    unreal.log("ROAM_EDITOR_LIB_SMOKE status=" + status)
    ok = ok and status.startswith("RoamEditorLibrary OK")

    total = unreal.RoamEditorLibrary.smoke_add(40, 2)
    unreal.log("ROAM_EDITOR_LIB_SMOKE add=%d" % total)
    ok = ok and total == 42

    unreal.log("ROAM_EDITOR_LIB_SMOKE settings=" + unreal.RoamEditorLibrary.describe_roam_settings())

    # runtime classes of the game module are visible to Python too
    for name in ("RoamGameMode", "RoamGameInstance", "RoamPlayerController", "RoamHUD", "RoamVehicle", "RoamCarDefinition",
                 "RoamCarCatalog", "RoamRoadNetwork", "RoamWorldDefinition"):
        present = hasattr(unreal, name)
        unreal.log("ROAM_EDITOR_LIB_SMOKE class %s present=%s" % (name, present))
        ok = ok and present
    # URoamSettings is a UDeveloperSettings: not exposed to Python as a class; use RoamEditorLibrary.describe_roam_settings().
except Exception as exc:  # noqa: BLE001 - report everything to the log
    unreal.log_error("ROAM_EDITOR_LIB_SMOKE exception: %r" % (exc,))
    ok = False

unreal.log("ROAM_EDITOR_LIB_SMOKE result=" + ("PASS" if ok else "FAIL"))
unreal.SystemLibrary.execute_console_command(None, "QUIT_EDITOR")
