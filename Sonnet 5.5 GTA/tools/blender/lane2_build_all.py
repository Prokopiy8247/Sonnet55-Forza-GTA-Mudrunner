"""lane2_build_all.py - rebuild + export every lane-2 vehicle (motorcycle, bicycle, ambulance, truck, firetruck, police_tactical) and save the master.
Run inside Blender (MCP) after loading gta_lib.py and lane2_common.py:
    exec(open(r"...\tools\blender\gta_lib.py", encoding="utf8").read(), globals()); assert_master()
    exec(open(r"...\tools\blender\lane2_common.py", encoding="utf8").read(), globals())
    exec(open(r"...\tools\blender\lane2_build_all.py", encoding="utf8").read(), globals())
Each asset script is idempotent (clear_asset first) and leaves its result in l2_A. Takes ~5 s in total.
"""
_L2DIR = os.path.join(PROJECT, "tools", "blender") + os.sep
for _f, _id in (("lane2_motorcycle.py", "motorcycle"), ("lane2_bicycle.py", "bicycle"), ("lane2_ambulance.py", "ambulance"),
                ("lane2_truck.py", "truck"), ("lane2_firetruck.py", "firetruck"), ("lane2_police_tactical.py", "police_tactical")):
    exec(open(_L2DIR + _f, encoding="utf8").read(), globals())
    l2_A.export("vehicles/" + _id)
save_master()
print("lane2: all six vehicles rebuilt, exported and saved")
