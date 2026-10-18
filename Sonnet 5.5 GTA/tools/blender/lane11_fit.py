r"""lane11_fit.py - QA fixtures for lane 11: a linked-duplicate reference sedan (shares the mesh data of sedan__* READ-ONLY, objects named
vpref__*) and part instances placed with the catalog mount transforms (vpfit__*). Nothing here is exported.
Load after gta_lib.py + lane11_common.py + lane11_catalog.py."""
import math
import bpy
from mathutils import Vector, Matrix, Euler

L11_REF_LOC = Vector((-40.0, 1900.0, 0.0))
L11_REF_COLL = "GTA_GODOT/Vehicles/Parts/_Reference"


def l11_adopt(o):
    root = bpy.data.objects.get("vpref__root")
    if root is not None:
        parent_to(o, root, keep_world=True)


def l11_make_ref(loc=None):
    loc = Vector(loc) if loc is not None else L11_REF_LOC
    clear_asset("vpref__")
    col = coll(L11_REF_COLL)
    empty("vpref__root", tuple(loc), collection=col, display="ARROWS", size=0.3)
    src = bpy.data.objects["sedan__root"]
    bpy.context.view_layer.update()
    T = Matrix.Translation(loc - src.matrix_world.translation)
    for o in descendants(src):
        if o.type != "MESH":
            continue
        n = bpy.data.objects.new("vpref__" + o.name.split(SEP, 1)[1], o.data)
        n.matrix_world = T @ o.matrix_world
        col.objects.link(n)
        l11_adopt(n)
    return loc


def l11_xf(pos, pitch=0.0, scale=(1, 1, 1), loc=None):
    loc = L11_REF_LOC if loc is None else loc
    return Matrix.Translation(loc + Vector(pos)) @ Euler((math.radians(pitch), 0, 0)).to_matrix().to_4x4() @ Matrix.Diagonal((scale[0], scale[1], scale[2], 1.0))


def l11_fit(ids, loc=None, clear=True):
    """place linked duplicates of the part meshes on the reference sedan with the catalog transforms."""
    if clear:
        clear_asset("vpfit__")
    col = coll(L11_REF_COLL)
    bpy.context.view_layer.update()
    n = 0
    for pid in ids:
        if pid.startswith("wheel_"):
            continue
        m = L11_MOUNT[pid]
        xf = l11_xf(m["pos"], m.get("pitch", 0.0), m.get("scale", (1, 1, 1)), loc)
        for node in ("Body",):
            src = bpy.data.objects.get(pid + SEP + node)
            if src is None:
                continue
            o = bpy.data.objects.new("vpfit__%s__%s" % (pid, node), src.data)
            o.matrix_world = xf
            col.objects.link(o)
            l11_adopt(o)
            n += 1
    return n


def l11_fit_wheels(styles, loc=None, scale=0.97):
    """styles: dict {"FL": "wheel_stock", ...}; hides the matching reference wheel."""
    col = coll(L11_REF_COLL)
    loc = L11_REF_LOC if loc is None else loc
    for k, pid in styles.items():
        ref = bpy.data.objects.get("vpref__Wheel_" + k)
        if ref is not None:
            ref.hide_viewport = True
            ref.hide_render = True
        pos = L11_SEDAN_WHEELS[k]
        xf = Matrix.Translation(loc + Vector(pos)) @ Matrix.Diagonal((1.0, scale, scale, 1.0))
        for node in ("Tire", "Rim"):
            src = bpy.data.objects.get(pid + SEP + node)
            if src is None:
                continue
            o = bpy.data.objects.new("vpfit__%s__%s_%s" % (pid, node, k), src.data)
            o.matrix_world = xf
            col.objects.link(o)
            l11_adopt(o)


def l11_fit_names():
    return [o.name for o in bpy.data.objects if o.name.startswith(("vpref__", "vpfit__"))]


L11_SHEET_LOC = Vector((-60.0, 1850.0, 0.0))


def l11_sheet(ids=None, loc=None, max_w=11.0, gap=0.3, skip=("underglow_strip",)):
    """Contact sheet: linked duplicates (shared mesh data) of every non-wheel part laid out in plan, rows wrapping at max_w metres.
    Parent: vpsheet__root. Returns the list of placed ids."""
    loc = Vector(loc) if loc is not None else L11_SHEET_LOC
    clear_asset("vpsheet__")
    col = coll(L11_REF_COLL)
    root = empty("vpsheet__root", tuple(loc), collection=col, display="ARROWS", size=0.3)
    ids = ids or [p for p in L11_ORDER if not p.startswith("wheel_")]
    x = y = 0.0
    row_h = 0.0
    placed = []
    for pid in ids:
        if pid in skip:
            continue
        src = bpy.data.objects.get(pid + SEP + "Body")
        if src is None:
            continue
        bb = [Vector(c) for c in src.bound_box]
        mn = Vector((min(v.x for v in bb), min(v.y for v in bb), min(v.z for v in bb)))
        mx = Vector((max(v.x for v in bb), max(v.y for v in bb), max(v.z for v in bb)))
        w, d = mx.x - mn.x, mx.y - mn.y
        if x > 0 and x + w > max_w:
            x = 0.0
            y -= row_h + gap
            row_h = 0.0
        o = bpy.data.objects.new("vpsheet__" + pid, src.data)
        o.location = Vector((x - mn.x, y - mx.y, 0.0))
        col.objects.link(o)
        parent_to(o, root)
        x += w + gap
        row_h = max(row_h, d)
        placed.append(pid)
    return placed
