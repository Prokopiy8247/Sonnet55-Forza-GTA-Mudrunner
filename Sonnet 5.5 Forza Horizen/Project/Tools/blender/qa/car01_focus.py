"""
car01_focus.py - QA helper: puts a tiny wire cube named car01_hatch_pulse_QAfocus at a point (car space, metres) so that
`look(target=['car01_hatch_pulse_QAfocus'], distance=1.2, views=[...])` frames a close-up there.
    FOCUS = (0.8, 0.6, 0.95)      # car-space point; FOCUS = None removes the helper
    exec(compile(open(r"<project>/Tools/blender/qa/car01_focus.py", encoding="utf8").read(), "qa", "exec"), globals())
The object is named with the car prefix (so remove_asset() deletes it) and is never part of the exported asset.
"""
import bpy
import bmesh
from mathutils import Vector

_NAME = "car01_hatch_pulse_QAfocus"
_root = bpy.data.objects.get("car01_hatch_pulse_ROOT")
_old = bpy.data.objects.get(_NAME)
_pt = globals().get("FOCUS")
if _old is not None:
    _me = _old.data
    bpy.data.objects.remove(_old, do_unlink=True)
    if _me is not None and _me.users == 0:
        bpy.data.meshes.remove(_me)
if _pt is not None and _root is not None:
    me = bpy.data.meshes.new(_NAME)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=globals().get("FOCUS_SIZE", 0.5))   # the viewport near clip scales with the target size
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(_NAME, me)
    col = bpy.data.collections.get("car01_hatch_pulse") or bpy.context.scene.collection
    col.objects.link(ob)
    ob.location = _root.location + Vector(_pt)
    ob.display_type = 'WIRE'
    print("focus at", tuple(ob.location))
