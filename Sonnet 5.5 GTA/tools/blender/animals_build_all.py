"""animals_build_all.py - rebuild + export every lane-12 animal (idempotent). Run after gta_lib.py:
    exec(open(r"W:\\YouTube\\Claude Sonnet 5.5\\GTA\\godot-sonnet-5.5gta\\tools\\blender\\gta_lib.py", encoding="utf8").read(), globals()); assert_master()
    EXPORT = True ; exec(open(r"...\\animals_build_all.py", encoding="utf8").read(), globals())
Set ONLY=['deer', ...] (asset ids) before exec to rebuild/export a subset; set EXPORT=False to skip the GLB export.
"""
import os
_D = r"W:\YouTube\Claude Sonnet 5.5\GTA\godot-sonnet-5.5gta\tools\blender"
_ONLY = globals().get("ONLY")
_EXPORT = globals().get("EXPORT", True)
_ALL = ["deer", "deer_buck", "dog", "cat", "seagull", "boar", "coyote", "rabbit", "cow", "bird_small", "fish_a", "fish_b", "shark",
        "dolphin", "sea_turtle", "horse", "seagull_perched", "bird_small_perched"]
_SCRIPTS = [("animals_deer.py", ("deer", "deer_buck")), ("animals_canines.py", ("dog", "coyote")), ("animals_small.py", ("cat", "rabbit")),
            ("animals_birds.py", ("seagull", "seagull_perched", "bird_small", "bird_small_perched")),
            ("animals_farm.py", ("boar", "cow", "horse")), ("animals_sea.py", ("fish_a", "fish_b", "shark", "dolphin", "sea_turtle"))]
for _f, _ids in _SCRIPTS:
    _want = [i for i in _ids if (_ONLY is None or i in _ONLY)]
    if not _want:
        continue
    ONLY = _want
    exec(open(os.path.join(_D, _f), encoding="utf8").read(), globals())
ONLY = _ONLY
if _EXPORT:
    for _a in _ALL:
        if (_ONLY is None or _a in _ONLY) and (_a + "__root") in bpy.data.objects:
            export_animal(_a)
    save_master()
