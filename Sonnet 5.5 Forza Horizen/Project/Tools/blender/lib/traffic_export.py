"""
traffic_export.py - validation + FBX/JSON export for traffic vehicles with a VARIABLE number of wheels
(Blender 5.2 / Python 3.13).  Load after carkit.py + carkit_ext_traffic.py (same globals):

    for _f in ("carkit.py", "carkit_ext_traffic.py", "traffic_export.py"):
        exec(compile(open(os.path.join(project, "Tools", "blender", "lib", _f), encoding="utf8").read(), _f, "exec"), globals())
    traffic_validate("traffic03_lorry_ROOT", targets=dict(length=8.5))
    traffic_export("traffic03_lorry_ROOT", extra=dict(...))

Conventions follow Docs/BLENDER_CONTRACT.md (axes, part pivots, FBX recipe through fbx_export.export_fbx) with these traffic rules:
  * parts: <id>_Body (+ UCX_<id>_Body_NN hulls), <id>_Glass, <id>_Interior (dark cabin), one <id>_Wheel_<key> per wheel
    (key FL/FR/RL/RR for 4-wheelers, 1..n for lorry / bus), origin of a wheel = axle centre of that wheel
  * every wheel carries custom properties: axle (0 = front), side ('L'/'R'), steering (bool), driven (bool), dual_with (name|'')
  * output Exports/Traffic/<id>/<id>_<Part>.fbx + <id>.json (positions in Blender car-space metres; UE: x*100, -y*100, z*100)
"""
import os
import re
import json
import math
import bpy
import bmesh
from mathutils import Vector, Matrix

TRAFFIC_BUDGET = (8000, 35000)
_ALLOWED_MATS = set(MAT_ORDER) | {'M_Traffic_Rust', 'M_Traffic_Wood'}


def _vs(ob):
    return [v.co for v in ob.data.vertices]


def _bbox(ob):
    vs = _vs(ob)
    return (Vector((min(a.x for a in vs), min(a.y for a in vs), min(a.z for a in vs))),
            Vector((max(a.x for a in vs), max(a.y for a in vs), max(a.z for a in vs))))


def vehicle_objects(vid):
    """dict: body, glass, interior, wheels (sorted list), ucx (sorted list), root"""
    root = bpy.data.objects.get(vid + "_ROOT")
    d = dict(root=root, body=bpy.data.objects.get(vid + "_Body"), glass=bpy.data.objects.get(vid + "_Glass"),
             interior=bpy.data.objects.get(vid + "_Interior"))
    d['wheels'] = sorted([o for o in bpy.data.objects if o.name.startswith(vid + "_Wheel_") and o.type == 'MESH'],
                         key=lambda o: (o.get('order', 0), o.name))
    d['ucx'] = sorted([o for o in bpy.data.objects if o.name.startswith("UCX_%s_Body_" % vid)], key=lambda o: o.name)
    return d


def wheel_info(w):
    mn, mx = _bbox(w)
    c = (mn + mx) / 2
    return dict(name=w.name, key=w.name.split("_Wheel_")[1], center=[round(a, 5) for a in w.location],
                radius=round((mx.z - mn.z) / 2, 5), width=round(mx.y - mn.y, 5), bbox_centre_xz=(round(c.x, 4), round(c.z, 4)),
                axle=int(w.get('axle', 0)), side=str(w.get('side', 'L' if w.location.y > 0 else 'R')),
                steering=bool(w.get('steering', False)), driven=bool(w.get('driven', False)),
                dual_with=str(w.get('dual_with', '')))


def traffic_validate(root_name, targets=None, budget=TRAFFIC_BUDGET, min_wheels=4, verbose=True):
    errors, warnings, stats = [], [], {}
    root = bpy.data.objects.get(root_name)
    if root is None:
        return dict(ok=False, errors=["root %s missing" % root_name], warnings=[], stats={})
    vid = root_name[:-5]
    ob = vehicle_objects(vid)
    for p in ROOT_PROPS:
        if p not in root.keys():
            errors.append("root custom property missing: " + p)
    parts = {}
    for k in ('body', 'glass', 'interior'):
        if ob[k] is None:
            errors.append("missing object %s_%s" % (vid, k.capitalize()))
        else:
            parts[k.capitalize()] = ob[k]
    if len(ob['wheels']) < min_wheels:
        errors.append("only %d wheels (< %d)" % (len(ob['wheels']), min_wheels))
    for w in ob['wheels']:
        parts[w.name[len(vid) + 1:]] = w
    if not (2 <= len(ob['ucx']) <= 6):
        errors.append("UCX hull count %d not in 2..6" % len(ob['ucx']))
    total = 0
    uv_info = {}
    mats = {}
    for pname, o in parts.items():
        me = o.data
        if o.parent is not root:
            errors.append(o.name + " is not parented to the root")
        if any(abs(a) > 1e-6 for a in o.rotation_euler) or any(abs(s - 1.0) > 1e-6 for s in o.scale):
            errors.append(o.name + " has rotation/scale not applied")
        if len(o.modifiers):
            errors.append(o.name + " still has modifiers")
        st = _mesh_stats(me)
        stats[pname] = st
        total += st['tris']
        if st['loose_verts'] or st['loose_edges']:
            errors.append("%s loose geometry: %d verts %d edges" % (o.name, st['loose_verts'], st['loose_edges']))
        if st['nonmanifold_edges']:
            errors.append("%s non-manifold edges (>2 faces): %d" % (o.name, st['nonmanifold_edges']))
        if st['flipped_islands']:
            errors.append("%s has %d closed islands with inverted normals" % (o.name, st['flipped_islands']))
        if st['degenerate']:
            warnings.append("%s degenerate faces: %d" % (o.name, st['degenerate']))
        names = [m.name if m else None for m in me.materials]
        mats[pname] = names
        for n in names:
            if n is None or n not in _ALLOWED_MATS:
                errors.append("%s material slot '%s' not in contract / traffic list" % (o.name, n))
        if pname == 'Body' and 'M_Paint' not in names:
            errors.append("Body has no M_Paint slot")
        if pname == 'Glass' and names != ['M_Glass']:
            warnings.append("Glass slots %s (expected only M_Glass)" % names)
        if pname != 'Glass' and 'M_Glass' in names:
            errors.append("%s uses the translucent M_Glass slot (only <id>_Glass may)" % o.name)
        if len(names) > 8 and pname == 'Body':
            warnings.append("Body has %d material slots (> 8)" % len(names))
        uvl = me.uv_layers.get('UVMap')
        if uvl is None:
            errors.append(o.name + " has no UVMap")
        else:
            ov = uv_overlap_ratio(me, res=384) if st['tris'] < 60000 else None
            uv_info[pname] = ov
            if ov is not None and ov > 0.02:
                errors.append("%s UV overlap %.1f%%" % (o.name, ov * 100))
            if any(not (-1e-4 <= u.uv.x <= 1 + 1e-4 and -1e-4 <= u.uv.y <= 1 + 1e-4) for u in uvl.data):
                errors.append(o.name + " UVs outside 0..1")
    stats['uv_overlap'] = uv_info
    stats['materials'] = mats
    # origins
    for pname in ('Body', 'Glass', 'Interior'):
        o = parts.get(pname)
        if o is not None and o.location.length > 1e-6:
            errors.append("%s origin is not the vehicle origin: %s" % (o.name, tuple(o.location)))
    # wheels
    winfo = []
    for w in ob['wheels']:
        wi = wheel_info(w)
        winfo.append(wi)
        if abs(wi['bbox_centre_xz'][0]) > 0.004 or abs(wi['bbox_centre_xz'][1]) > 0.004:
            errors.append("%s pivot not at the axle centre (bbox centre %s)" % (w.name, wi['bbox_centre_xz']))
        if abs(w.location.z - wi['radius']) > 0.004:
            errors.append("%s axle height %.4f != radius %.4f (tyre does not touch z=0)" % (w.name, w.location.z, wi['radius']))
        if (wi['side'] == 'L' and w.location.y <= 0) or (wi['side'] == 'R' and w.location.y >= 0):
            errors.append("%s on the wrong side" % w.name)
    stats['wheels'] = winfo
    if winfo:
        a_min, a_max = min(w['axle'] for w in winfo), max(w['axle'] for w in winfo)
        for key, ax in (('front', a_min), ('rear', a_max)):
            mw = max(w['width'] for w in winfo if w['axle'] == ax)
            have = root.get('wheel_width_' + key)
            if have is not None and abs(have - mw) > 0.003:
                warnings.append("ROOT wheel_width_%s = %.4f but the measured tyre width is %.4f" % (key, have, mw))
    # dimensions
    body = ob['body']
    if body is not None:
        mn, mx = _bbox(body)
        dims = dict(length=mx.x - mn.x, width_with_mirrors=mx.y - mn.y, height=mx.z, min_z=mn.z)
        stats['dims'] = {k: round(v, 3) for k, v in dims.items()}
        if mn.z < 0.02:
            errors.append("Body dips to z=%.3f" % mn.z)
        if targets:
            for k, tv in targets.items():
                have = root.get(k)
                if have is not None and abs(have - tv) > max(0.05, tv * 0.03):
                    warnings.append("%s = %.3f differs from target %.3f" % (k, have, tv))
    for h in ob['ucx']:
        if len(h.data.vertices) > 32:
            errors.append("%s has %d verts (> 32)" % (h.name, len(h.data.vertices)))
        if not _is_convex(h.data):
            errors.append("%s is not convex" % h.name)
        hmn, hmx = _bbox(h)
        if min(hmx.x - hmn.x, hmx.y - hmn.y, hmx.z - hmn.z) < 0.15:
            errors.append("%s is only %.3f m thick (< 0.15 m: useless / degenerate collision hull)" % (h.name, min(hmx.x - hmn.x, hmx.y - hmn.y, hmx.z - hmn.z)))
        if h.parent is not root:
            errors.append(h.name + " not parented to root")
    stats['ucx'] = [(h.name, len(h.data.vertices)) for h in ob['ucx']]
    stats['total_tris'] = total
    if not (budget[0] <= total <= budget[1]):
        warnings.append("total triangles %d outside the %d-%d budget" % (total, budget[0], budget[1]))
    ok = not errors
    if verbose:
        print("=== traffic_validate(%s): %s | tris %d | wheels %d ===" % (vid, "OK" if ok else "FAILED", total, len(ob['wheels'])))
        for k, st in stats.items():
            if k in parts:
                print("  %-12s tris %6d verts %6d open-edges %4d ngons %4d islands closed/open %d/%d uv-overlap %s" % (
                    k, st['tris'], st['verts'], st['boundary_edges'], st['ngons'], st['closed_islands'], st['open_islands'],
                    ("%.2f%%" % (uv_info.get(k, 0) * 100)) if uv_info.get(k) is not None else "n/a"))
        print("  dims:", stats.get('dims'))
        print("  ucx:", stats['ucx'])
        for e in errors:
            print("  ERROR  ", e)
        for w in warnings:
            print("  warning", w)
    return dict(ok=ok, errors=errors, warnings=warnings, stats=stats)


def _uv_copy(src, dst):
    """Copy the UVMap loop data of src to dst (identical topology / loop order required)."""
    import numpy as np
    a = src.data.uv_layers['UVMap'].data
    n = len(a)
    arr = np.empty(n * 2, dtype=np.float32)
    a.foreach_get('uv', arr)
    if dst.data.uv_layers.get('UVMap') is None:
        dst.data.uv_layers.new(name='UVMap')
    dst.data.uv_layers['UVMap'].data.foreach_set('uv', arr)
    dst.data.update()


def uv_wheels(vid, only=None):
    """UV every wheel; wheels with the same topology (same side / loop count / polygon count) copy the UVs of the first one."""
    groups = {}
    n = 0
    for w in vehicle_objects(vid)['wheels']:
        if only is not None and w.name[len(vid) + 1:] not in only:
            continue
        key = (w.get('side', ''), len(w.data.loops), len(w.data.polygons))
        if key in groups:
            _uv_copy(groups[key], w)
        else:
            uv_unwrap(w)
            groups[key] = w
        n += 1
    return n


def uv_parts(vid, which=None):
    """UV-unwrap parts of a vehicle (which = list among 'Body', 'Glass', 'Interior', 'Wheels' or a single wheel name; None = all).
    Split the work over several MCP calls (each < 20 s)."""
    ob = vehicle_objects(vid)
    n = 0
    for k in ('body', 'glass', 'interior'):
        if ob[k] is not None and (which is None or k.capitalize() in which):
            uv_unwrap(ob[k])
            n += 1
    if which is None or 'Wheels' in which:
        n += uv_wheels(vid)
    else:
        n += uv_wheels(vid, only=[w for w in which if w.startswith('Wheel_')])
    return n


_FBX2 = {}


def _fbx_fn():
    if 'fn' not in _FBX2:
        path = os.path.join(project_dir(), 'Tools', 'blender', 'lib', 'fbx_export.py')
        ns = {'__name__': 'fbx_export'}
        exec(compile(open(path, encoding='utf8').read(), path, 'exec'), ns)
        _FBX2['fn'] = ns['export_fbx']
    return _FBX2['fn']


def traffic_export(root_name, out_dir=None, extra=None, display_name=None):
    """FBX per part + JSON sidecar in Exports/Traffic/<id>/ .  `extra` = dict merged into the JSON (paint_variants, usage, ...)."""
    export_fbx = _fbx_fn()
    root = bpy.data.objects[root_name]
    vid = root_name[:-5]
    out_dir = out_dir or os.path.join(project_dir(), 'Exports', 'Traffic', vid)
    os.makedirs(out_dir, exist_ok=True)
    bpy.context.view_layer.update()
    ob = vehicle_objects(vid)
    ucx = ob['ucx']
    written = {}

    def out(part):
        return os.path.join(out_dir, "%s_%s.fbx" % (vid, part))

    jobs = [('Body', [vid + '_Body'] + [h.name for h in ucx], root), ('Glass', [vid + '_Glass'], root),
            ('Interior', [vid + '_Interior'], root)]
    for w in ob['wheels']:
        jobs.append((w.name[len(vid) + 1:], [w.name], 'self'))
    hid = [(h, h.hide_get()) for h in ucx]
    vl = bpy.context.view_layer
    prev_active = vl.objects.active
    prev_sel = [o for o in vl.objects if o.select_get()]
    for h, _ in hid:
        h.hide_set(False)
    try:
        for part, names, center in jobs:
            p = export_fbx(names, out(part), center_on=center)
            written[part] = p
            if p is None or not os.path.exists(p):
                raise RuntimeError("FBX export failed for " + part)
    finally:
        for h, was in hid:
            h.hide_set(was)
        for o in [o for o in vl.objects if o.select_get()]:
            o.select_set(False)
        for o in prev_sel:
            try:
                o.select_set(True)
            except Exception:
                pass
        vl.objects.active = prev_active

    def P(name):
        o = bpy.data.objects.get(name)
        return [round(c, 5) for c in o.location] if o is not None else None

    mn, mx = _bbox(ob['body'])
    wl = [wheel_info(w) for w in ob['wheels']]
    for wi in wl:
        wi['file'] = "%s_%s.fbx" % (vid, wi['name'][len(vid) + 1:])
        wi.pop('bbox_centre_xz', None)
    axles = {}
    for wi in wl:
        a = axles.setdefault(wi['axle'], dict(index=wi['axle'], x=wi['center'][0], steering=wi['steering'], driven=wi['driven'], wheels=[]))
        a['wheels'].append(wi['name'])
    data = {
        "id": vid, "display_name": display_name or root.get('display_name', vid), "category": "traffic", "units": "m",
        "dimensions": {"length": round(float(root['length']), 4), "width": round(float(root['width']), 4),
                       "height": round(float(root['height']), 4), "width_with_mirrors": round(mx.y - mn.y, 4)},
        "wheelbase": round(float(root['wheelbase']), 4), "track_front": round(float(root['track_front']), 4),
        "track_rear": round(float(root['track_rear']), 4), "ride_height": round(float(root['ride_height']), 4),
        "wheel_count": len(wl), "wheels": wl, "axles": [axles[k] for k in sorted(axles)],
        "cameras": {k.replace('CAM_', '').lower(): P(vid + '_' + k) for k in
                    [o.name[len(vid) + 1:] for o in bpy.data.objects if o.name.startswith(vid + '_CAM_')]},
        "lights": {re.sub(r'(head|tail)([lr])$', r'\g<1>_\g<2>', k.replace('LP_', '').lower()): P(vid + '_' + k) for k in
                   [o.name[len(vid) + 1:] for o in bpy.data.objects if o.name.startswith(vid + '_LP_')]},
        "exhaust": [P(o.name) for o in sorted([o for o in bpy.data.objects if o.name.startswith(vid + '_EXHAUST')], key=lambda o: o.name)],
        "material_slots": {}, "tri_counts": {}, "ucx": [h.name for h in ucx],
        "files": {k: os.path.basename(v) for k, v in written.items()},
        "ue_import": {"ue_x": "x*100", "ue_y": "-y*100", "ue_z": "z*100", "forward": "+X", "note":
                      "one FBX per part, pivot = vehicle origin (Body/Glass/Interior) or axle centre (wheels)"},
    }
    for k in ('Body', 'Glass', 'Interior'):
        o = ob[k.lower()]
        data['material_slots'][k] = [m.name for m in o.data.materials if m]
        data['tri_counts'][k] = tri_count(o.data)
    for w in ob['wheels']:
        pn = w.name[len(vid) + 1:]
        data['material_slots'][pn] = [m.name for m in w.data.materials if m]
        data['tri_counts'][pn] = tri_count(w.data)
    data['tri_counts']['UCX'] = sum(tri_count(h.data) for h in ucx)
    data['tri_counts']['total_visual'] = sum(v for k, v in data['tri_counts'].items() if k not in ('UCX', 'total_visual'))
    if len(wl) == 4 and all(w['key'] in ('FL', 'FR', 'RL', 'RR') for w in wl):
        data['wheel_map'] = {w['key']: dict(center=w['center'], radius=w['radius'], width=w['width']) for w in wl}
    if extra:
        data.update(extra)
    jp = os.path.join(out_dir, vid + '.json')
    with open(jp, 'w', encoding='utf8') as fh:
        json.dump(data, fh, indent=2)
    written['json'] = jp
    res = {k: (v, os.path.getsize(v)) for k, v in written.items()}
    for k, (v, sz) in res.items():
        print("  %-14s %9d bytes  %s" % (k, sz, v))
    return res
