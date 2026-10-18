"""
ground_cover.py - idempotent GROUND COVER kit builder (bushes, rocks, cliffs, cacti, grass, flowers, crops, hay, wood, reeds, beach props, sign).
Run inside the shared MCP Blender (:9889):
    NS = {'GC_IDS': ['nat_rock_granite_a'], 'GC_EXPORT': False}
    P = r"<project>/Tools/blender/nature/ground_cover.py"
    exec(compile(open(P, encoding='utf8').read(), P, 'exec'), NS)
GC_IDS may also contain group names: 'bushes','rocks','cliffs','cacti','grass','misc'.
Files: gc_lib.py (core) | gc_rocks.py | gc_plants.py | gc_misc.py (asset builders registering into ASSETS) | this file (harness, validation, export)
"""
import os
_DIR = os.path.join(r"W:\YouTube\Claude Sonnet 5.5\Forza Horizen\Sonnet55Forza\UnrealSonnet55Forza", "Tools", "blender", "nature")
for _f in ('gc_lib.py',):
    _p = os.path.join(_DIR, _f); exec(compile(open(_p, encoding='utf8').read(), _p, 'exec'), globals())

ASSETS = {}
GROUPS = {}
def reg(aid, group, **kw):
    kw['group'] = group; ASSETS[aid] = kw; GROUPS.setdefault(group, []).append(aid)

for _f in ('gc_rocks.py', 'gc_plants.py', 'gc_misc.py'):
    _p = os.path.join(_DIR, _f)
    if os.path.exists(_p): exec(compile(open(_p, encoding='utf8').read(), _p, 'exec'), globals())

def stage_positions():
    xs = {}; x = STAGE_X0; prev = 0.0
    for aid, s in ASSETS.items():
        w = s.get('w', 3.0)
        if prev: x += prev / 2 + w / 2 + 3.0
        xs[aid] = x; prev = w
    return xs

def validate(aid, obj, ucx_objs, spec):
    s = mesh_stats(obj)
    rep = dict(id=aid, **s)
    rep['scale_ok'] = tuple(round(x, 4) for x in obj.scale) == (1.0, 1.0, 1.0) and all(abs(a) < 1e-6 for a in obj.rotation_euler)
    rep['ground_ok'] = bool(-0.6 < s['bbox_min'][2] <= 0.0)
    rep['uv'] = [u.name for u in obj.data.uv_layers]
    uvd = np.empty(len(obj.data.uv_layers[0].data) * 2, dtype=np.float32); obj.data.uv_layers[0].data.foreach_get('uv', uvd)
    rep['uv_finite'] = bool(np.isfinite(uvd).all())
    cols = np.empty(len(obj.data.color_attributes['Col'].data) * 4, dtype=np.float32); obj.data.color_attributes['Col'].data.foreach_get('color', cols)
    cols = cols.reshape(-1, 4)
    rep['col_range'] = [[round(float(cols[:, k].min()), 2), round(float(cols[:, k].max()), 2)] for k in range(3)]
    rep['materials'] = [m.name for m in obj.data.materials]
    rep['mat_ok'] = 0 < len(rep['materials']) <= 4
    rep['ucx'] = {}
    for uo in ucx_objs:
        bm = bmesh.new(); bm.from_mesh(uo.data)
        convex = all(e.calc_face_angle_signed(0.0) >= -1e-4 for e in bm.edges if len(e.link_faces) == 2)
        rep['ucx'][uo.name] = dict(verts=len(uo.data.vertices), convex=convex, manifold=all(len(e.link_faces) == 2 for e in bm.edges))
        bm.free()
    lo, hi = spec.get('budget', (100, 12000))
    rep['tri_ok'] = lo <= s['tris'] <= hi
    rep['name_ok'] = obj.name == aid and all(n.startswith('UCX_' + aid + '_') for n in rep['ucx'])
    if spec.get('closed', False): rep.update(island_check(obj))
    else: rep.update(closed_pieces=0, open_pieces=-1, inverted_closed_pieces=0)
    return rep

def export_asset(aid, obj, ucx_names, rep, spec):
    fbx_lib()
    bpy.context.view_layer.update()
    path = os.path.join(EXPORT_DIR, aid + '.fbx')
    with contextlib.redirect_stdout(io.StringIO()):
        p1 = export_fbx([aid] + ucx_names, path, center_on='self', extra_kwargs=dict(colors_type='LINEAR'))
    size = [round(rep['bbox_max'][k] - rep['bbox_min'][k], 3) for k in range(3)]
    foliage = spec.get('wind', False)
    js = dict(
        id=aid, display_name=spec['name'], kit='ground_cover', family=spec['group'], units='m',
        origin=spec.get('origin', 'base centre on the ground (z=0); +Z up; +X = front'),
        dimensions=dict(x=size[0], y=size[1], z=size[2], height=rep['bbox_max'][2]),
        bounds=dict(min=rep['bbox_min'], max=rep['bbox_max']),
        tri_counts=dict(mesh=rep['tris'], ucx=[len(bpy.data.objects[n].data.polygons) for n in ucx_names]),
        material_slots=rep['materials'],
        collision=dict(type=('convex' if ucx_names else 'none'), ucx_hulls=ucx_names,
                       notes=spec.get('coll_note', 'UCX_* convex hulls (<=32 verts). UE: Collision Complexity = Use Simple As Complex' if ucx_names else 'no collision (foliage / decoration)')),
        biome_tags=spec['biome'], scale_range=list(spec['scale']),
        wind=(dict(vertex_color='Col', export_colors='LINEAR (raw 0-1 masks)', R='flex 0 (root) -> 1 (tip / outer shell)', G='flutter 0 -> 1 (free tips)', B='baked AO-ish occlusion (1 = open)', A='per-element random 0-1 (tint / phase variation)',
                   hint='WPO: sway = R^2 * low-freq wind; flutter = G * high-freq noise; multiply base colour by lerp(0.35,1,B); use A for per-leaf hue shift') if foliage else dict(vertex_color='Col', B='baked AO-ish occlusion (1 = open)', note='static, no wind')),
        lod=dict(nanite=spec.get('nanite', 'recommended (opaque modelled geometry, no alpha cards)')),
        two_sided_material=bool(foliage), uv='UVMap ' + spec.get('uvnote', 'box-projected, tiling at 2 m per UV unit (rocks) / per-element 0-1 (foliage cards)'),
        quality=dict(closed_pieces=rep['closed_pieces'], open_pieces=rep['open_pieces'], inverted_closed_pieces=rep['inverted_closed_pieces'], nonmanifold_edges=rep['nonmanifold_edges']),
        files=dict(fbx='Exports/Nature/Cover/%s.fbx' % aid), generator='Tools/blender/nature/ground_cover.py (seed %d)' % spec['seed'])
    if spec.get('extra'): js.update(spec['extra'])
    with open(os.path.join(EXPORT_DIR, aid + '.json'), 'w', encoding='utf8') as f: json.dump(js, f, indent=2)
    return p1

def build(aid, export=False, verbose=True):
    t0 = time.time()
    spec = ASSETS[aid]
    remove_asset(aid)
    mb = MB(); rng = random.Random(spec['seed'])
    info = spec['fn'](mb, rng, spec['P']) or {}
    if spec.get('sink') is not None: mb.ground(spec['sink'])
    mats = ensure_materials(mb.mats)
    me = mb_to_mesh(mb, aid, mats)
    col = get_cover_collection()
    x = stage_positions()[aid]
    obj = bpy.data.objects.new(aid, me); col.objects.link(obj); obj.location = (x, STAGE_Y, 0.0)
    # collision hulls
    V = np.array(mb.V); G = np.array(mb.G); ucx = []
    mode = spec.get('coll', 'none'); hulls = []
    if mode == 'groups':
        for g in sorted(set(G.tolist())):
            if g > 0: hulls.append(hull_points(V[G == g], spec.get('ndir', 24)))
        if not hulls: hulls.append(hull_points(V, spec.get('ndir', 24)))
    elif mode == 'all': hulls.append(hull_points(V, spec.get('ndir', 24)))
    elif mode == 'slabs':
        n = info.get('slabs', 4); main = (G == 0); xs = V[:, 0]; edges = np.linspace(xs[main].min(), xs[main].max(), n + 1)
        for k in range(n):
            sel = main & (xs >= edges[k] - 1e-6) & (xs <= edges[k + 1] + 1e-6)
            if sel.sum() >= 6: hulls.append(hull_points(V[sel], spec.get('ndir', 24)))
        for g in info.get('hull_groups', []): hulls.append(hull_points(V[G == g], spec.get('ndir', 24)))
    elif mode == 'custom': hulls = [np.asarray(h) for h in info['hulls']]
    for k, h in enumerate(hulls, 1):
        ucx.append(make_hull('UCX_%s_%02d' % (aid, k), h, obj, col))
    rep = validate(aid, obj, ucx, spec)
    ucx_names = [o.name for o in ucx]
    rep['seconds'] = round(time.time() - t0, 2)
    if export:
        rep['exported'] = export_asset(aid, obj, ucx_names, rep, spec)
    try:
        rp = os.path.join(EXPORT_DIR, 'validation_report.json')
        allr = json.load(open(rp, encoding='utf8')) if os.path.exists(rp) else {}
        allr[aid] = rep
        with open(rp, 'w', encoding='utf8') as f: json.dump(allr, f, indent=1)
    except Exception as e: print('report write failed', e)
    if verbose:
        bad = [k for k in ('scale_ok', 'ground_ok', 'uv_finite', 'tri_ok', 'name_ok', 'mat_ok') if not rep.get(k)]
        if rep['inverted_closed_pieces']: bad.append('inverted')
        if rep['nonmanifold_edges']: bad.append('nonmanifold')
        if any((not v['convex']) or v['verts'] > 32 for v in rep['ucx'].values()): bad.append('ucx')
        sz = [round(rep['bbox_max'][k] - rep['bbox_min'][k], 2) for k in range(3)]
        print('%-26s tris %6d size %s ucx %d mats %d %s %.1fs%s' % (aid, rep['tris'], sz, len(rep['ucx']), len(rep['materials']), ('FAIL ' + ','.join(bad)) if bad else 'ok', rep['seconds'], ' exported' if export else ''))
    return obj, rep

def run(ids, export=False):
    todo = []
    for i in ids:
        if i in GROUPS: todo += GROUPS[i]
        elif i == 'all': todo += list(ASSETS)
        else: todo.append(i)
    for aid in todo:
        try: build(aid, export=export)
        except Exception as e:
            import traceback; print('ERROR', aid, e); traceback.print_exc()

if 'GC_IDS' in globals():
    run(GC_IDS, export=globals().get('GC_EXPORT', False))
