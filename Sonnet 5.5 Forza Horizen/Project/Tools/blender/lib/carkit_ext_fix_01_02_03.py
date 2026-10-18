"""
carkit_ext_fix_01_02_03.py - clean-up helpers added in the art-director fix round for the player cars 01 Pulse / 02 Cadence /
03 Thunderline.  Load AFTER carkit.py (and carkit_ext_02_03_04.py) into the same namespace:
    exec(compile(open(FIX, encoding="utf8").read(), FIX, "exec"), globals())
Nothing here edits carkit.py; it only uses its public functions (heal_nonmanifold, log ...).

purge_qa(car)               remove every QA-only object of one car (<car>_FOC_* edge meshes, <car>_QA_* lights) + their datablocks
cleanup_slivers(bm, ...)    weld / dissolve the near-zero-area boolean fans (area < 1e-7 m2) that the kit's finish_object() leaves
                            behind (it only works at 1e-6 m / 1e-10 m2), then repair the non-manifold edges a weld can create
fix_micro_islands(bm, ...)  tiny closed islands (dial ticks, knobs): recalculate their normals outward; drop open specks
mesh_quality(obj_or_mesh)   read-only health numbers (small faces, non-manifold, boundary) for the QA printout
"""
import math
import bpy
import bmesh
from mathutils import Vector


def purge_qa(car):
    """Delete the QA clutter of one car: edge-only focus meshes `<car>_FOC_*` and area lights `<car>_QA_*` (objects + data)."""
    n = 0
    for o in [o for o in bpy.data.objects if o.name.startswith(car + "_FOC_") or o.name.startswith(car + "_QA_")]:
        data, typ = o.data, o.type
        bpy.data.objects.remove(o, do_unlink=True)
        if data is not None and data.users == 0:
            if typ == 'MESH':
                bpy.data.meshes.remove(data)
            elif typ == 'LIGHT':
                bpy.data.lights.remove(data)
        n += 1
    for m in [m for m in bpy.data.meshes if m.name.startswith(car + "_FOC_") and m.users == 0]:
        bpy.data.meshes.remove(m)
    for l in [l for l in bpy.data.lights if l.name.startswith(car + "_QA_") and l.users == 0]:
        bpy.data.lights.remove(l)
    return n


def _drop_loose(bm):
    le = [e for e in bm.edges if not e.link_faces]
    if le:
        bmesh.ops.delete(bm, geom=le, context='EDGES')
    lv = [v for v in bm.verts if not v.link_edges]
    if lv:
        bmesh.ops.delete(bm, geom=lv, context='VERTS')


def cleanup_slivers(bm, area=1e-7, weld=2.5e-4, passes=4, verbose=True):
    """Boolean fans leave ~1 000 near-zero-area faces (< 1e-7 m2) per body: UE can turn them into NaN tangents / Nanite warnings.
    Per pass: weld the vertices of every face below `area` to their neighbours within `weld` metres, dissolve the degenerate
    geometry that this creates and repair the edges with more than two faces (heal_nonmanifold).  Only vertices that belong to a
    sliver are welded, so nothing else moves (the weld distance is 0.25 mm; the smallest intended detail is a 3.5 mm bevel).
    Returns (faces_before_small, faces_after_small)."""
    bm.faces.ensure_lookup_table()
    before = sum(1 for f in bm.faces if f.calc_area() < area)
    for _ in range(passes):
        bad = [f for f in bm.faces if f.calc_area() < area]
        if not bad:
            break
        vs = list({v for f in bad for v in f.verts})
        bmesh.ops.remove_doubles(bm, verts=vs, dist=weld)
        bm.verts.ensure_lookup_table()
        bm.edges.ensure_lookup_table()
        try:
            bmesh.ops.dissolve_degenerate(bm, dist=1e-4, edges=list(bm.edges))
        except Exception as ex:                     # pragma: no cover
            print("cleanup_slivers: dissolve_degenerate failed:", ex)
        bm.faces.ensure_lookup_table()
        dead = [f for f in bm.faces if f.calc_area() < 1e-11]
        if dead:
            bmesh.ops.delete(bm, geom=dead, context='FACES')
        _drop_loose(bm)
        heal_nonmanifold(bm, max_area=2e-4)
        bm.faces.ensure_lookup_table()
    # whatever is still non-manifold after the weld is a sliver sheet: keep the two biggest faces per edge
    heal_nonmanifold(bm, max_area=5e-4, passes=6)
    _drop_loose(bm)
    # the welds / dissolves can merge triangles into n-gons (> 4 verts); Blender's FBX exporter then silently drops the TANGENT
    # layers of the whole mesh (use_tspace needs tris / quads): triangulate them again (beauty), like finish_object() does
    bm.faces.ensure_lookup_table()
    ng = [f for f in bm.faces if len(f.verts) > 4]
    if ng:
        bmesh.ops.triangulate(bm, faces=ng, quad_method='BEAUTY', ngon_method='BEAUTY')
        bm.faces.ensure_lookup_table()
        sl = [f for f in bm.faces if f.calc_area() < 1e-10]
        if sl:
            bmesh.ops.remove_doubles(bm, verts=list({v for f in sl for v in f.verts}), dist=2e-5)
            bm.faces.ensure_lookup_table()
            dead = [f for f in bm.faces if f.calc_area() < 1e-10]
            if dead:
                bmesh.ops.delete(bm, geom=dead, context='FACES')
            _drop_loose(bm)
            heal_nonmanifold(bm, max_area=5e-4, passes=3)
            bm.faces.ensure_lookup_table()
            ng2 = [f for f in bm.faces if len(f.verts) > 4]
            if ng2:
                bmesh.ops.triangulate(bm, faces=ng2, quad_method='BEAUTY', ngon_method='BEAUTY')
    bm.faces.ensure_lookup_table()
    bm.normal_update()
    after = sum(1 for f in bm.faces if f.calc_area() < area)
    if verbose:
        print("[cleanup_slivers] faces below %.0e m2: %d -> %d | non-manifold edges %d | faces %d" % (
            area, before, after, sum(1 for e in bm.edges if len(e.link_faces) > 2), len(bm.faces)))
    return before, after


def fix_micro_islands(bm, max_dim=0.015, drop_open_below=0.004):
    """Islands (connected face groups) smaller than `max_dim` metres: closed ones (dial ticks, knobs, nuts) get consistent outward
    normals (bmesh.ops.recalc_face_normals on the island), open specks smaller than `drop_open_below` are deleted.
    Returns (recalculated, dropped)."""
    bm.faces.ensure_lookup_table()
    seen = set()
    recalc_n, dropped = 0, 0
    kill = []
    for f0 in list(bm.faces):
        if f0 in seen:
            continue
        stack, isl = [f0], []
        seen.add(f0)
        while stack:
            f = stack.pop()
            isl.append(f)
            for e in f.edges:
                for nf in e.link_faces:
                    if nf not in seen:
                        seen.add(nf)
                        stack.append(nf)
        vs = {v for f in isl for v in f.verts}
        dim = max(max(v.co[i] for v in vs) - min(v.co[i] for v in vs) for i in range(3))
        if dim > max_dim:
            continue
        closed = all(len(e.link_faces) == 2 for f in isl for e in f.edges)
        if closed and len(isl) <= 4:          # two back-to-back triangles (a welded sliver sheet) - not a solid, just junk
            kill.extend(isl)
            dropped += 1
        elif closed:
            bmesh.ops.recalc_face_normals(bm, faces=isl)
            recalc_n += 1
        elif dim < drop_open_below:
            kill.extend(isl)
            dropped += 1
    if kill:
        bmesh.ops.delete(bm, geom=kill, context='FACES')
        _drop_loose(bm)
    return recalc_n, dropped


def build_taillight_clean(surf, center, ray, axes, length=0.30, height=0.066, rot=0.10, depth=0.016, n=56, p=3.0,
                          bezel_mat='M_Chrome', bezel_w=0.0095, bezel_h=0.0024, rib=0.0, split=0.20, a_split=0.20,
                          bulge=0.0035, lens_inset=0.0042, red_mat='M_Taillight', margin=(0.013, 0.011)):
    """Wrap-around tail lamp for the LEFT side, same (cutter_bm, [insert_bms]) contract as carkit.build_taillight, but clean:
    a SHALLOW pocket (`depth`) with an all-black floor (nothing behind the translucent preview lens: no LED bars / reflector /
    grey floor that read as a messy mix of paint and lens), one smooth red lens (top ~60 %) over an amber indicator (outer, +U)
    and a white reverse window (inner, -U), a thin chrome separator line and a chrome bezel strip on the cut edge (hides the
    ragged boolean edge, reads as the lens rim).  `split` = position of the split line below the centre as a fraction of the
    half height, `a_split` = fraction of the half length (inner | outer window)."""
    U, V = Vector(axes[0]), Vector(axes[1])
    cr, sr = math.cos(rot), math.sin(rot)

    def Rot(q):
        return (q[0] * cr - q[1] * sr, q[0] * sr + q[1] * cr)
    outline = [Rot(q) for q in outline_superellipse(length, height, p, n)]
    cut = pocket_cutter(surf, outline, center, ray, depth=depth, lift=0.03, taper=1.0, mat='M_TrimBlack', axes=(U, V))
    if cut is None:
        return None, []
    c = Vector(center)
    ins = []
    bz = surface_sweep(surf, [c + U * q[0] + V * q[1] for q in outline], ray, rib_profile(bezel_w, bezel_h, 0.006, 0.0011),
                       closed=True, mat=bezel_mat)
    if bz is not None:
        ins.append(bz)
    Lg, Hg = length - margin[0], height - margin[1]
    lens_o = outline_superellipse(Lg, Hg, p, n)
    b_s = -split * Hg
    a_s = -a_split * Lg
    top = clip_poly(lens_o, 0.0, 1.0, -(b_s + rib / 2))
    low = clip_poly(lens_o, 0.0, -1.0, (b_s - rib / 2))
    segs = [(top, red_mat),
            (clip_poly(low, 1.0, 0.0, -(a_s + rib / 2)), 'M_Indicator'),
            (clip_poly(low, -1.0, 0.0, (a_s - rib / 2)), 'M_Reverse')]
    for poly, mat in segs:
        if len(poly) < 3:
            continue
        poly = densify_outline(poly, 0.010)            # a straight seam across the curved corner would sag below the skin (black wedge)
        ca, cb = poly_centroid(poly)
        rel = [Rot((q[0] - ca, q[1] - cb)) for q in poly]
        cu, cv = Rot((ca, cb))
        ins.append(surface_patch(surf, rel, c + U * cu + V * cv, ray, offset=lens_inset, rings=3, mat=mat, axes=(U, V), bulge=bulge))
    # thin chrome separator between the red lens and the lower row, and between amber | white
    hl = Lg * (1.0 - min(abs(b_s) / Hg, 0.999) ** p) ** (1.0 / p) * 0.97
    line = [c + U * Rot((-hl + 2 * hl * i / 12.0, b_s))[0] + V * Rot((-hl + 2 * hl * i / 12.0, b_s))[1] for i in range(13)]
    sep = surface_sweep(surf, line, ray, rib_profile(0.0036, 0.0024, 0.005, 0.0008), mat='M_Chrome')
    if sep is not None:
        ins.append(sep)
    return cut, [b for b in ins if b is not None]


def shear_end(shell, end='rear', zone=0.50, lean=0.05, z_lo=0.40, z_hi=0.97, power=1.25):
    """Lean the end fascia of a lofted shell: vertices within `zone` metres of the end station (and the dome caps beyond it) move
    towards the car centre by up to `lean` m, growing with height (0 below z_lo, full above z_hi) and smoothly with the distance to
    the end.  The end fascia is a vertical slab after loft_body(); a few degrees of rake (Thunderline tail: 5 cm over 55 cm ~ 5 deg)
    reads as a designed tail instead of a cut-off one.  Everything that refers to the shell afterwards stays consistent:
    shell.bm, the private smooth reference shell (shell.ref + its BVH, used by apply_shell_normals) and shell.pos are moved the same way.
    Call it right after loft_body() and BEFORE Surface(shell.bm)."""
    from mathutils.bvhtree import BVHTree
    xs = shell.xs
    x_end = xs[0] if end == 'rear' else xs[-1]
    sgn = 1.0 if end == 'rear' else -1.0                    # move towards the car centre

    def new_x(co):
        d = abs(co.x - x_end) if (co.x - x_end) * sgn >= 0 else 0.0   # distance from the end station inwards
        outside = (co.x - x_end) * sgn < 0                          # dome cap beyond the end station
        t = 1.0 if outside else max(0.0, 1.0 - d / zone)
        w = t * t * (3.0 - 2.0 * t)
        tz = min(max((co.z - z_lo) / (z_hi - z_lo), 0.0), 1.0) ** power
        return co.x + sgn * lean * w * tz
    for v in shell.bm.verts:
        v.co.x = new_x(v.co)
    for v in shell.ref.verts:
        v.co.x = new_x(v.co)
    shell.bm.normal_update()
    shell.ref.normal_update()
    shell.ref.faces.ensure_lookup_table()
    shell.ref_bvh = BVHTree.FromBMesh(shell.ref)
    shell.pos = [[Vector(v.co) for v in row] for row in shell.rows]
    return shell


def uv_unwrap_packed(ob, angle=66.0, margin=0.0015, layer_name="UVMap"):
    """Like carkit.uv_unwrap (smart project + pack, selection / active object restored) but with a tight island margin: the Body
    sheet has ~1 400 small islands and the kit's 0.004 margin ate ~75 % of the sheet (27 % texel usage); margin 0.0015 (3 px at
    2k, 6 px at 4k) gives ~46 % at the same non-overlap.  The pack call is explicit (concave shapes, free rotation)."""
    vl = bpy.context.view_layer
    prev_active = vl.objects.active
    prev_sel = [o for o in vl.objects if o.select_get()]
    try:
        for o in prev_sel:
            o.select_set(False)
        ob.select_set(True)
        vl.objects.active = ob
        for l in list(ob.data.uv_layers):
            ob.data.uv_layers.remove(l)
        ob.data.uv_layers.new(name=layer_name)
        bpy.ops.object.mode_set(mode='EDIT')
        bpy.ops.mesh.select_all(action='SELECT')
        bpy.ops.uv.smart_project(angle_limit=math.radians(angle), island_margin=margin, area_weight=0.0, correct_aspect=True,
                                 scale_to_bounds=False)
        try:
            bpy.ops.uv.pack_islands(margin=margin, rotate=True, margin_method='SCALED', shape_method='CONCAVE')
        except Exception:
            bpy.ops.uv.pack_islands(margin=margin, rotate=True)
        bpy.ops.object.mode_set(mode='OBJECT')
    finally:
        try:
            if bpy.context.mode != 'OBJECT':
                bpy.ops.object.mode_set(mode='OBJECT')
        except Exception:
            pass
        ob.select_set(False)
        for o in prev_sel:
            try:
                o.select_set(True)
            except Exception:
                pass
        vl.objects.active = prev_active
    if ob.data.uv_layers and ob.data.uv_layers[0].name != layer_name:
        ob.data.uv_layers[0].name = layer_name
    return ob


def unwrap_parts_fix(car, parts, body_margin=0.0015):
    """UVs of the listed parts (suffixes): Body gets the tight packing + the UVLivery channel, everything else the kit default."""
    import time as _t
    t0 = _t.time()
    for suf in parts:
        o = bpy.data.objects.get("%s_%s" % (car, suf))
        if o is None:
            continue
        if suf == 'Body':
            uv_unwrap_packed(o, margin=body_margin)
            uv_livery_layer(o)
        else:
            uv_unwrap(o)
        print("[%s] uv %s %.1fs" % (car, suf, _t.time() - t0))


def uv_utilisation(me, layer="UVMap"):
    """Fraction of the 0..1 sheet covered by UV triangles (sum of triangle areas; the islands do not overlap)."""
    import numpy as np
    uvl = me.uv_layers[layer]
    uv = np.empty(len(me.loops) * 2, dtype=np.float32)
    uvl.data.foreach_get('uv', uv)
    uv = uv.reshape(-1, 2)
    me.calc_loop_triangles()
    tr = np.empty(len(me.loop_triangles) * 3, dtype=np.int32)
    me.loop_triangles.foreach_get('loops', tr)
    Pp = uv[tr.reshape(-1, 3)]
    return float(0.5 * np.abs((Pp[:, 1, 0] - Pp[:, 0, 0]) * (Pp[:, 2, 1] - Pp[:, 0, 1])
                              - (Pp[:, 2, 0] - Pp[:, 0, 0]) * (Pp[:, 1, 1] - Pp[:, 0, 1])).sum())


def export_car_checked(root_name, display_name=None, quiet=True):
    """carkit.export_car() + a read-back check of every written FBX: it must contain the tangent / binormal layers (Blender's exporter
    silently drops them for a mesh with n-gons, which shrinks the file to ~40 % and leaves UE without imported tangents) and the
    UV layers (Body 2, the other parts 1).  Also checks that the exported file is newer than the scene state (written just now).
    Returns {part: (path, bytes)}; raises RuntimeError when a check fails."""
    import io
    import os
    import time
    import contextlib
    t0 = time.time() - 2.0
    buf = io.StringIO()
    if quiet:
        with contextlib.redirect_stdout(buf):
            res = export_car(root_name, display_name=display_name)
    else:
        res = export_car(root_name, display_name=display_name)
    bad = []
    for part, (path, size) in res.items():
        if part == 'json':
            continue
        b = open(path, 'rb').read()
        n_uv = 2 if part == 'Body' else 1
        tang, binm = b.count(b'LayerElementTangent'), b.count(b'LayerElementBinormal')
        if tang < 2 * n_uv or binm < 2 * n_uv:
            bad.append("%s: tangent layers %d / binormal %d (expected >= %d) - n-gons in the mesh?" % (part, tang, binm, 2 * n_uv))
        if os.path.getmtime(path) < t0:
            bad.append("%s: file is older than this export call" % part)
    if bad:
        raise RuntimeError("export check failed: " + "; ".join(bad))
    return res


def fix_object_micro_islands(ob, max_dim=0.015, drop_open_below=0.004):
    """fix_micro_islands() on a finished mesh object (finish_object()'s own clean-up can weld a 2-face junk sheet again, so run this
    right after it and BEFORE apply_shell_normals / the UV unwrap).  Returns (recalculated, dropped)."""
    me = ob.data
    bm = bmesh.new()
    bm.from_mesh(me)
    b, a = cleanup_slivers(bm, verbose=False)      # finish_object()'s beauty triangulation of the n-gons leaves a few dozen new slivers
    r = fix_micro_islands(bm, max_dim=max_dim, drop_open_below=drop_open_below)
    bm.to_mesh(me)
    me.update()
    bm.free()
    print("[fix_object_micro_islands] %s: slivers %d -> %d, micro islands: %d solids fixed, %d junk islands dropped" % (ob.name, b, a, r[0], r[1]))
    return r


def mesh_quality(ob_or_me, area=1e-7):
    me = ob_or_me.data if hasattr(ob_or_me, 'data') and not isinstance(ob_or_me, bpy.types.Mesh) else ob_or_me
    bm = bmesh.new()
    bm.from_mesh(me)
    d = dict(faces=len(bm.faces), small=sum(1 for f in bm.faces if f.calc_area() < area),
             tiny=sum(1 for f in bm.faces if f.calc_area() < 1e-9),
             nonmanifold=sum(1 for e in bm.edges if len(e.link_faces) > 2),
             boundary=sum(1 for e in bm.edges if len(e.link_faces) == 1))
    bm.free()
    return d
