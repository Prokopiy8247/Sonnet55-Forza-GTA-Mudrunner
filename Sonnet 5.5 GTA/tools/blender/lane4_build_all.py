"""lane4_build_all.py - rebuild EVERYTHING for characters/human (rig is kept unless C4_REBUILD_RIG=True is set before exec).
Usage inside Blender (after gta_lib.py):  exec(open(<this file>).read(), globals())"""
_D = os.path.join(PROJECT, "tools", "blender") + os.sep
exec(open(_D + "lane4_lib.py", encoding="utf8").read(), globals())
C4_REBUILD_RIG = bool(globals().get("C4_REBUILD_RIG", False))
exec(open(_D + "lane4_rig.py", encoding="utf8").read(), globals())
C4_KINDS = ["A", "B", "C"]
exec(open(_D + "lane4_body.py", encoding="utf8").read(), globals())
exec(open(_D + "lane4_head.py", encoding="utf8").read(), globals())
for _f in ("lane4_hair.py", "lane4_hats.py", "lane4_gear.py"):
    C4_ONLY = None
    del C4_ONLY
    exec(open(_D + _f, encoding="utf8").read(), globals())
