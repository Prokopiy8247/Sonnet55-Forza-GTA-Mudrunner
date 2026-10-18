"""
qa_focus.py - tiny QA helper for close-up `look` calls (shared Blender session safe: object name = <car_id>_QAF_focus, removed by
remove_asset(car_id) and by qa_focus(car_id, None)).
    exec(compile(open(QAF, encoding="utf8").read(), QAF, "exec"), globals())
    qa_focus("car05_gt_meridian", (62.3, 0, 0.4), 1.2)     # then look(target=["car05_gt_meridian_QAF_focus"], views=[...], distance=1.6)
look() frames the target's bounding box and sets the clip planes from it, so a point-like target gets a tiny frustum.  This helper
provides an invisible mesh (two loose vertices, no edges / faces: nothing is drawn in any shading mode) whose bounding box is a
cube of the wanted size at the wanted world position.
"""
import bpy


def qa_focus(car_id, center=None, size=1.0):
    name = car_id + "_QAF_focus"
    ob = bpy.data.objects.get(name)
    if center is None:
        if ob is not None:
            me = ob.data
            bpy.data.objects.remove(ob, do_unlink=True)
            if me.users == 0:
                bpy.data.meshes.remove(me)
        return None
    if ob is None:
        me = bpy.data.meshes.new(name)
        s = 0.5
        me.from_pydata([(-s, -s, -s), (s, s, s)], [], [])
        me.update()
        ob = bpy.data.objects.new(name, me)
        col = bpy.data.collections.get(car_id) or bpy.context.scene.collection
        col.objects.link(ob)
        ob.hide_render = True
    ob.scale = (size, size, size)
    ob.location = center
    bpy.context.view_layer.update()
    return ob
