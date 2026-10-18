"""lane7: rebuild + export every hero landmark building (run inside Blender through the MCP connection):
    exec(open(r"W:\\YouTube\\Claude Sonnet 5.5\\GTA\\godot-sonnet-5.5gta\\tools\\blender\\lane7_build_all.py", encoding="utf8").read(), globals())
Each lane7_<id>.py is idempotent (clear_asset first) and ends with a stats report. Export writes gta/generated/models/buildings/<id>.glb.
After that run:  powershell -NoProfile -File tools\\gd.ps1 import   and   gd.ps1 script -Script res://gta/tests/glb_probe.gd -GameArgs "buildings/<id>"
"""
import os
_T = r"W:\YouTube\Claude Sonnet 5.5\GTA\godot-sonnet-5.5gta\tools\blender"
exec(open(os.path.join(_T, "gta_lib.py"), encoding="utf8").read(), globals())
assert_master()
exec(open(os.path.join(_T, "lane7_lib.py"), encoding="utf8").read(), globals())
ORDER = ["police_station", "hospital", "weapon_shop", "garage_shop", "safehouse", "gas_station", "clothing_store", "barber", "scuba_shop",
         "train_station", "parking_garage"]
for _id in ORDER:
    exec(open(os.path.join(_T, "lane7_%s.py" % _id), encoding="utf8").read(), globals())
    export_glb(bpy.data.objects[_id + "__root"], "buildings/" + _id)
# the world asks for two station buildings; train_station_b sits in a shallower lot (21.2 m) -> squeezed variant
export_glb(bpy.data.objects["train_station__root"], "buildings/train_station_a")
exec(open(os.path.join(_T, "lane7_export_variants.py"), encoding="utf8").read(), globals())
save_master()
