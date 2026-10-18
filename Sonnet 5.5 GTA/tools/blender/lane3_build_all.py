"""lane3_build_all.py - rebuild (and optionally export) every lane-3 asset: heli_civil, speedboat, plane_prop, heli_police, plane_jet.

Run inside Blender (MCP execute_blender_code), after gta_lib.py:
    exec(open(r"W:\\YouTube\\Claude Sonnet 5.5\\GTA\\godot-sonnet-5.5gta\\tools\\blender\\gta_lib.py", encoding="utf8").read(), globals())
    L3_EXPORT = True          # False = only rebuild in the master scene
    exec(open(r"W:\\YouTube\\Claude Sonnet 5.5\\GTA\\godot-sonnet-5.5gta\\tools\\blender\\lane3_build_all.py", encoding="utf8").read(), globals())
Each asset is idempotent (clear_asset first) and lives in its own workshop slot (workshop(3, 0..4, 25)).
After exporting run:  powershell -NoProfile -File tools\\gd.ps1 import   and   gd.ps1 script -Script res://gta/tests/glb_probe.gd -GameArgs "vehicles/<id>"
Visual check in Godot:  gd.ps1 shot ... --exec=res://gta/tests/vehicles_lane3_showcase.gd   (env VEH_SHOW=<id>, VEH_POSE=1 deflects control surfaces / rotors)
"""
import os
_here = os.path.join(PROJECT, "tools", "blender")
for _nm in ("lane3_heli_civil", "lane3_speedboat", "lane3_plane_prop", "lane3_heli_police", "lane3_plane_jet"):
    exec(open(os.path.join(_here, _nm + ".py"), encoding="utf8").read(), globals())
