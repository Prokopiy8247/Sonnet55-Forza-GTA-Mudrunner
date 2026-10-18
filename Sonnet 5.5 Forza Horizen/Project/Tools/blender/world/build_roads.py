"""
build_roads.py - Blender side of the road pipeline ("Roamline: Open Roads", agent R 'road-meshes').

Run inside the verified Blender MCP session (localhost:9889), idempotent:

    p = r"<project>/Tools/blender/world/build_roads.py"
    g = {"__file__": p}
    exec(compile(open(p, encoding="utf8").read(), p, "exec"), g)
    g["build"](only=["HWY_EAST"])            # or g["build"]() for the whole network
    g["validate"]()                          # surface-Z / budget / NaN checks
    g["export"]()                            # FBX per chunk + Exports/Roads/chunks.json
    bpy.ops.wm.save_mainfile()

The geometry itself comes from roadgeo.py / roadstruct.py (pure numpy, also runnable with the plain interpreter).
Collections: FORZA_UE/Roads (surface chunks + junction pads), FORZA_UE/Bridges_Tunnels (bridges + tunnels).
Object / mesh / FBX / UE names:  RC_<road>_<nn> surface, RJ_<node> junction pad, RB_<road>_<nn> bridge, RT_<road>_<nn> tunnel.
"""
import contextlib
import io
import json
import math
import os
import sys
import time
import importlib

import bpy
import numpy as np

ROOT = globals().get("ROAMLINE_ROOT") or r"W:\YouTube\Claude Sonnet 5.5\Forza Horizen\Sonnet55Forza\UnrealSonnet55Forza"
WORLD_DIR = os.path.join(ROOT, "Tools", "blender", "world")
ROADS_JSON = os.path.join(ROOT, "Tools", "world", "out", "roads.json")
HEIGHTMAP = os.path.join(ROOT, "Content", "Forza", "World", "Source", "heightmap_4033.r16")
EXPORT_DIR = os.path.join(ROOT, "Exports", "Roads")
USER_PROMPT = "Build a polished original open-world racing game in UE5.8 with Blender-authored assets"

if WORLD_DIR not in sys.path:
    sys.path.insert(0, WORLD_DIR)
import roadgeo as rg
import roadstruct as rs
import roadbuild as rb
for _m in (rg, rs, rb):
    importlib.reload(_m)
rb.ROOT = ROOT           # the Blender session passes the project root explicitly
rb.ROADS_JSON, rb.HEIGHTMAP = ROADS_JSON, HEIGHTMAP

PREFIXES = ("RC_", "RJ_", "RB_", "RT_")


# ----------------------------------------------------------------------------------------------------------------------
# collections / materials
def ensure_collection(path):
    parent = bpy.context.scene.collection
    col = None
    for part in path.split("/"):
        col = next((c for c in parent.children if c.name == part), None)
        if col is None:
            col = bpy.data.collections.get(part)
            if col is None:
                col = bpy.data.collections.new(part)
            if col.name not in [c.name for c in parent.children]:
                parent.children.link(col)
        parent = col
    return col


def _set(node, name, value):
    sock = node.inputs.get(name)
    if sock is not None:
        sock.default_value = value


def _mat_simple(name, color, rough=0.8, metal=0.0, emit=None, emit_strength=0.0):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    _set(bsdf, "Base Color", tuple(color) + (1.0,))
    _set(bsdf, "Roughness", rough)
    _set(bsdf, "Metallic", metal)
    if emit is not None:
        _set(bsdf, "Emission Color", tuple(emit) + (1.0,))
        _set(bsdf, "Emission Strength", emit_strength)
    mat.diffuse_color = tuple(color) + (1.0,)
    return mat, nt, bsdf


def _math(nt, op, a=None, b=None, c=None, clamp=False):
    n = nt.nodes.new("ShaderNodeMath")
    n.operation = op
    n.use_clamp = clamp
    for i, v in enumerate((a, b, c)):
        if v is None:
            continue
        if isinstance(v, (int, float)):
            n.inputs[i].default_value = float(v)
        else:
            nt.links.new(v, n.inputs[i])
    return n.outputs[0]


def _asphalt_material():
    """Preview asphalt with procedurally drawn lane markings (edge lines, centre / lane dashes) from UV1 / UV2 / UV3."""
    mat, nt, bsdf = _mat_simple("M_Road_Asphalt", (0.045, 0.045, 0.05), 0.82)
    # attribute reads
    uv1 = nt.nodes.new("ShaderNodeUVMap"); uv1.uv_map = "UV1"
    uv2 = nt.nodes.new("ShaderNodeUVMap"); uv2.uv_map = "UV2"
    uv3 = nt.nodes.new("ShaderNodeUVMap"); uv3.uv_map = "UV3"
    s1 = nt.nodes.new("ShaderNodeSeparateXYZ"); nt.links.new(uv1.outputs["UV"], s1.inputs[0])
    s2 = nt.nodes.new("ShaderNodeSeparateXYZ"); nt.links.new(uv2.outputs["UV"], s2.inputs[0])
    s3 = nt.nodes.new("ShaderNodeSeparateXYZ"); nt.links.new(uv3.outputs["UV"], s3.inputs[0])
    d, s = s1.outputs["X"], s1.outputs["Y"]
    P, lw = s2.outputs["X"], s2.outputs["Y"]
    med, zone = s3.outputs["X"], s3.outputs["Y"]
    ad = _math(nt, "ABSOLUTE", d)
    # edge line at |d| = P - 0.25, width 0.16
    e_dist = _math(nt, "ABSOLUTE", _math(nt, "SUBTRACT", ad, _math(nt, "SUBTRACT", P, 0.25)))
    edge = _math(nt, "LESS_THAN", e_dist, 0.08)
    # lane divider: no median -> centre line (|d| < 0.08); median -> |d| = med/2 + lw
    m2 = _math(nt, "MULTIPLY", med, 0.5)
    div_pos = _math(nt, "ADD", m2, _math(nt, "MULTIPLY", lw, 1.0))
    has_med = _math(nt, "GREATER_THAN", med, 0.1)
    # position of the divider line: has_med ? m2 + lw : 0
    pos = _math(nt, "MULTIPLY", div_pos, has_med)
    dd = _math(nt, "ABSOLUTE", _math(nt, "SUBTRACT", ad, pos))
    divl = _math(nt, "LESS_THAN", dd, 0.07)
    # only roads with 2 lanes per direction or no median (centre line) draw it: median roads need P > m2 + lw + 0.2
    ok_div = _math(nt, "MAXIMUM", _math(nt, "SUBTRACT", 1.0, has_med),
                   _math(nt, "GREATER_THAN", P, _math(nt, "ADD", div_pos, 0.2)))
    # dashes: 3 m paint / 9 m period
    saw = _math(nt, "FRACT", _math(nt, "DIVIDE", s, 9.0))
    dash = _math(nt, "LESS_THAN", saw, 0.34)
    divl = _math(nt, "MULTIPLY", _math(nt, "MULTIPLY", divl, dash), ok_div)
    # median edge lines (yellow-ish handled as white): |d| = med/2 + 0.12
    # carriageway only (zone ~ 1) and a real road (P > 0.5)
    on_road = _math(nt, "MULTIPLY", _math(nt, "GREATER_THAN", zone, 0.9), _math(nt, "GREATER_THAN", P, 0.5))
    paint = _math(nt, "MULTIPLY", _math(nt, "MAXIMUM", edge, divl), on_road)
    # wear noise
    tc = nt.nodes.new("ShaderNodeTexCoord")
    noise = nt.nodes.new("ShaderNodeTexNoise"); noise.inputs["Scale"].default_value = 2.2
    noise.inputs["Detail"].default_value = 6.0
    nt.links.new(tc.outputs["Object"], noise.inputs["Vector"])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = (0.035, 0.035, 0.04, 1.0)
    ramp.color_ramp.elements[1].color = (0.075, 0.075, 0.08, 1.0)
    nt.links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
    mix = nt.nodes.new("ShaderNodeMix"); mix.data_type = "RGBA"
    nt.links.new(paint, mix.inputs["Factor"])
    nt.links.new(ramp.outputs["Color"], mix.inputs["A"])
    mix.inputs["B"].default_value = (0.78, 0.78, 0.72, 1.0)
    nt.links.new(mix.outputs["Result"], bsdf.inputs["Base Color"])
    return mat


def ensure_materials():
    mats = {}
    try:
        mats["M_Road_Asphalt"] = _asphalt_material()
    except Exception as e:                    # keep the pipeline alive even if the node API differs
        print("asphalt preview material fallback:", e)
        mats["M_Road_Asphalt"] = _mat_simple("M_Road_Asphalt", (0.05, 0.05, 0.055), 0.85)[0]
    mats["M_Road_Concrete"] = _mat_simple("M_Road_Concrete", (0.36, 0.35, 0.33), 0.8)[0]
    mats["M_Road_Dirt"] = _mat_simple("M_Road_Dirt", (0.26, 0.17, 0.10), 0.95)[0]
    mats["M_Road_Gravel"] = _mat_simple("M_Road_Gravel", (0.30, 0.27, 0.23), 0.95)[0]
    mats["M_Curb"] = _mat_simple("M_Curb", (0.52, 0.51, 0.47), 0.8)[0]
    mats["M_Bridge_Concrete"] = _mat_simple("M_Bridge_Concrete", (0.42, 0.41, 0.39), 0.85)[0]
    mats["M_Bridge_Steel"] = _mat_simple("M_Bridge_Steel", (0.50, 0.53, 0.57), 0.45, metal=0.85)[0]
    mats["M_Tunnel_Wall"] = _mat_simple("M_Tunnel_Wall", (0.50, 0.48, 0.43), 0.9)[0]
    mats["M_Tunnel_Light"] = _mat_simple("M_Tunnel_Light", (1.0, 0.92, 0.75), 0.5, emit=(1.0, 0.88, 0.62), emit_strength=15.0)[0]
    mats["M_Road_Marking"] = _mat_simple("M_Road_Marking", (0.85, 0.85, 0.8), 0.6)[0]
    return mats


# ----------------------------------------------------------------------------------------------------------------------
# planning (pure numpy, see roadbuild.py)
make_plan = rb.make_plan
chunk_data = rb.chunk_data


# ----------------------------------------------------------------------------------------------------------------------
# object creation
def remove_objects(ids=None):
    n = 0
    for colname in ("Roads", "Bridges_Tunnels"):
        col = bpy.data.collections.get(colname)
        if col is None:
            continue
        for ob in list(col.objects):
            if not ob.name.startswith(PREFIXES):
                continue
            if ids is not None and ob.name not in ids:
                continue
            me = ob.data
            bpy.data.objects.remove(ob, do_unlink=True)
            if me is not None and me.users == 0:
                bpy.data.meshes.remove(me)
            n += 1
    return n


def make_object(name, data, mats, collection):
    """Create the Blender object for one chunk.  Origin = centre of the bounding box (rounded to 1 cm)."""
    V = data["V"]
    centre, lo, hi = rb.centre_of(V)
    Vl = (V - centre).astype(np.float32)
    F = data["F"].astype(np.int64)
    me = bpy.data.meshes.new(name)
    me.from_pydata(Vl.tolist(), [], F.tolist())
    # UV layers, indexed per loop
    li = F.ravel()
    for k in range(4):
        uv = me.uv_layers.new(name="UV%d" % k)
        uv.data.foreach_set("uv", data["UV"][k][li].astype(np.float32).ravel())
    # materials: compact to the used slots, in material-id order
    used = sorted(set(data["M"].tolist()))
    remap = {m: i for i, m in enumerate(used)}
    for m in used:
        me.materials.append(mats[rg.MATS[m]])
    me.polygons.foreach_set("material_index", np.array([remap[m] for m in data["M"].tolist()], np.int32))
    me.polygons.foreach_set("use_smooth", np.ones(len(F), bool))
    me.update()
    ob = bpy.data.objects.new(name, me)
    ob.location = tuple(float(c) for c in centre)
    collection.objects.link(ob)
    return ob, centre, lo, hi, [rg.MATS[m] for m in used]


def build(only=None, kinds=None, clean=True, verbose=True):
    t0 = time.time()
    plan = make_plan(only, kinds)
    mats = ensure_materials()
    col_roads = ensure_collection("FORZA_UE/Roads")
    col_bt = ensure_collection("FORZA_UE/Bridges_Tunnels")
    ids = [c["id"] for c in plan["chunks"]]
    if clean:
        remove_objects(set(ids) if (only or kinds) else None)
    out = []
    for c in plan["chunks"]:
        data, extra = chunk_data(plan, c)
        if data is None:
            continue
        col = col_bt if c["kind"] in ("bridge", "tunnel") else col_roads
        ob, centre, lo, hi, slots = make_object(c["id"], data, mats, col)
        rec = rb.chunk_record(c, data, extra)
        ob["roam_chunk"] = json.dumps({k: rec[k] for k in ("id", "kind", "road", "s0", "s1", "tris")})
        out.append(rec)
        if verbose:
            print("%-34s %-8s tris=%6d  size=%s" % (c["id"], c["kind"], rec["tris"], [round(x) for x in rec["size_m"]]))
    print("built %d chunks in %.1fs, %d tris" % (len(out), time.time() - t0, sum(r["tris"] for r in out)))
    return out


# ----------------------------------------------------------------------------------------------------------------------
# validation
def _chunk_objects():
    out = {}
    for colname in ("Roads", "Bridges_Tunnels"):
        col = bpy.data.collections.get(colname)
        if col:
            for ob in col.objects:
                if ob.name.startswith(PREFIXES):
                    out[ob.name] = ob
    return out


def validate(samples_per_chunk=24, tol=0.01, only=None, verbose=True):
    """Surface-Z check on the REAL Blender meshes: rays cast on lane centres of every road / bridge / tunnel chunk must hit the top
    surface within `tol` (1 cm) of the analytic profile height, with an upward normal.  Also: NaN check, triangle budget, counts."""
    import mathutils
    from mathutils.bvhtree import BVHTree
    plan = make_plan(only)
    objs = _chunk_objects()
    dg = bpy.context.evaluated_depsgraph_get()
    rng = np.random.default_rng(7)
    report = dict(chunks=0, tris=0, max_dz=0.0, rays=0, misses=0, bad_normal=0, nan=0, worst=None, over_budget=[], small=[])
    for c in plan["chunks"]:
        ob = objs.get(c["id"])
        if ob is None:
            continue
        report["chunks"] += 1
        me = ob.data
        co = np.empty(len(me.vertices) * 3, np.float32)
        me.vertices.foreach_get("co", co)
        if not np.isfinite(co).all():
            report["nan"] += 1
        nt = len(me.polygons)
        report["tris"] += nt
        if nt > 40000:
            report["over_budget"].append((c["id"], nt))
        if nt < 8000:
            report["small"].append((c["id"], nt))
        if c["kind"] == "junction":
            continue
        road = plan["roads"][c["road"]]
        bvh = BVHTree.FromObject(ob, dg)
        loc = np.array(ob.location)
        ss = rng.uniform(c["s0"] + 1.0, c["s1"] - 1.0, samples_per_chunk) if c["s1"] - c["s0"] > 3 else []
        if c["kind"] == "tunnel":
            ss = [s for s in ss]
        if road.med > 0:
            ds = [-(road.med / 2 + road.lw * 1.5), -(road.med / 2 + road.lw * 0.5), road.med / 2 + road.lw * 0.5,
                  road.med / 2 + road.lw * 1.5]
        else:
            ds = [-road.P / 2, 0.0, road.P / 2]
        for s in ss:
            fr = road.at(s)
            d = ds[int(rng.integers(len(ds)))]
            x = fr["x"][0] + fr["ty"][0] * d
            y = fr["y"][0] - fr["tx"][0] * d
            ze = float(road.surface_z(s, d)[0])
            origin = mathutils.Vector((x - loc[0], y - loc[1], ze + 1.0 - loc[2]))
            hit = bvh.ray_cast(origin, mathutils.Vector((0, 0, -1)), 3.0)
            report["rays"] += 1
            if hit[0] is None:
                report["misses"] += 1
                continue
            dz = abs(hit[0].z + loc[2] - ze)
            if hit[1].z < 0.5:
                report["bad_normal"] += 1
                report.setdefault("bad_normal_info", []).append((c["id"], round(float(s), 1), round(float(d), 2), [round(v, 2) for v in hit[1]]))
            if dz > report["max_dz"]:
                report["max_dz"] = dz
                report["worst"] = (c["id"], float(s), float(d), float(dz))
            if dz > tol:
                report.setdefault("outside_tol", []).append((c["id"], round(float(s), 1), round(float(d), 2), round(dz, 4)))
    if verbose:
        print("VALIDATE chunks=%d tris=%d rays=%d misses=%d bad_normal=%d nan=%d max_dz=%.4f m worst=%s" % (
            report["chunks"], report["tris"], report["rays"], report["misses"], report["bad_normal"], report["nan"],
            report["max_dz"], report["worst"]))
        print("  over 40k tris:", report["over_budget"], " | chunks below 8k tris:", len(report["small"]))
        print("  outside tol:", report.get("outside_tol", [])[:10])
    return report


# ----------------------------------------------------------------------------------------------------------------------
# export
def _exec_fbx_helper():
    path = os.path.join(ROOT, "Tools", "blender", "lib", "fbx_export.py")
    ns = {"__name__": "fbx_export", "__file__": path}
    exec(compile(open(path, encoding="utf8").read(), path, "exec"), ns)
    return ns["export_fbx"]


def export(only=None, kinds=None, limit=None, skip_existing=False):
    """One FBX per chunk -> Exports/Roads/<chunk id>.fbx (each chunk centred on its own origin = chunk centre)."""
    export_fbx = _exec_fbx_helper()
    plan = make_plan(only, kinds)
    objs = _chunk_objects()
    os.makedirs(EXPORT_DIR, exist_ok=True)
    n, t0 = 0, time.time()
    for c in plan["chunks"]:
        ob = objs.get(c["id"])
        if ob is None:
            print("missing object", c["id"])
            continue
        fp = os.path.join(EXPORT_DIR, c["id"] + ".fbx")
        if skip_existing and os.path.exists(fp):
            continue
        with contextlib.redirect_stdout(io.StringIO()):          # the FBX exporter prints two lines per file
            res = export_fbx([ob], fp, center_on="self", mesh_smooth="FACE")
        if not res:
            print("EXPORT FAILED", c["id"])
        n += 1
        if limit and n >= limit:
            break
    print("exported %d FBX in %.1fs" % (n, time.time() - t0))
    return n


def write_manifest(path=None):
    """Exports/Roads/chunks.json: every chunk (centre, bounds, road, class, s-range, material slots, tris, FBX file) + global data."""
    plan = make_plan()
    recs = []
    for c in plan["chunks"]:
        data, extra = chunk_data(plan, c)
        rec = rb.chunk_record(c, data, extra)
        rec["fbx"] = "Exports/Roads/%s.fbx" % c["id"]
        recs.append(rec)
    roads = plan["roads"]
    by_road = {}
    for r in recs:
        if r["road"]:
            by_road.setdefault(r["road"], []).append(r["id"])
    culverts = []
    for rid, r in roads.items():
        for s in r.rd.get("culverts", []):
            fr = r.at(s)
            culverts.append(dict(road=rid, s=float(s), pos_ue_m=[float(fr["x"][0]), float(-fr["y"][0]), float(fr["z"][0])],
                                 heading_deg=float(math.degrees(math.atan2(-fr["ty"][0], fr["tx"][0])) % 360.0),
                                 bed_half_width_m=r.B, surface=r.surface))
    holes = []
    for r in recs:
        for h in r.get("landscape_holes", []):
            holes.append(dict(chunk=r["id"], **h))
    import make_hole_mask as mhm
    importlib.reload(mhm)
    hv = mhm.hole_vertices(holes, plan)
    man = dict(
        version=1, generator="Tools/blender/world/build_roads.py", units="m", source="Tools/world/out/roads.json",
        coordinate_system=dict(
            chunk_centre_ue_m="UE metres X north, Y east, Z up; mesh origin == chunk centre; FBX is exported centred so "
                              "UE actor location (cm) = centre_ue_m * 100",
            blender="(x, y, z) = (X_ue, -Y_ue, Z)"),
        materials=rg.MATS,
        uv_channels=dict(UV0="(u 0..1 across the mesh width, v = s/10)", UV1="(lateral metres from centre line, right +; arc length s in metres)",
                         UV2="(paved half width m, lane width m); (0, 3) on junction pads = no markings",
                         UV3="(median width m, zone: 1 carriageway, .66 shoulder, .5 curb / pavement, .33 barrier / parapet, 0 skirt)"),
        collision="complex_as_simple (use the render triangles); no UCX hulls",
        nanite=True,
        stats=dict(chunks=len(recs), tris=sum(r["tris"] for r in recs),
                   by_kind={k: sum(1 for r in recs if r["kind"] == k) for k in ("road", "junction", "bridge", "tunnel")},
                   bridge_deck_buried_ranges=sum(len(r["deck_buried"]["ranges"]) for r in recs if "deck_buried" in r),
                   terrain_above_road_ranges=sum(len(r["terrain_above_road"]) for r in recs if "terrain_above_road" in r)),
        roads={rid: dict(chunks=ids, **{"class": roads[rid].cls, "surface": roads[rid].surface, "length_m": roads[rid].L})
               for rid, ids in by_road.items()},
        chunks=recs, culverts=culverts, landscape_holes=holes,
        landscape_hole_vertices=dict(
            note="heightmap vertices (i, j) = (X_ue + 2016, Y_ue + 2016) to hide with the Landscape visibility layer: tunnel mouths "
                 "(rectangles above) + quads where the natural terrain stands above a bridge deck (chunk field deck_buried); "
                 "Tools/blender/world/make_hole_mask.py writes the same set as a 4033 x 4033 uint8 raster",
            count=int(len(hv)), vertices=hv.tolist()))
    path = path or os.path.join(EXPORT_DIR, "chunks.json")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf8") as f:
        json.dump(man, f, indent=1)
    print("wrote", path, "chunks", len(recs), "tris", man["stats"]["tris"])
    return man


# ----------------------------------------------------------------------------------------------------------------------
# QA helpers
def qa_focus(road_id=None, s=None, size=(30, 30, 10), loc=None, name="rd_qa_focus"):
    """Create/move a temporary wire box (object `name`) so `look(target=[name])` frames a place on a road.  Remove with qa_clear()."""
    import bmesh
    if loc is None:
        net, roads = rg.load_network(ROADS_JSON)
        fr = roads[road_id].at(s)
        loc = (float(fr["x"][0]), float(fr["y"][0]), float(fr["z"][0]))
    ob = bpy.data.objects.get(name)
    if ob is not None:
        me = ob.data
        bpy.data.objects.remove(ob, do_unlink=True)
        if me is not None and me.users == 0:
            bpy.data.meshes.remove(me)
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co.x *= size[0]; v.co.y *= size[1]; v.co.z *= size[2]
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    ob.display_type = "WIRE"
    ob.hide_render = True
    bpy.context.scene.collection.objects.link(ob)
    ob.location = loc
    return ob


def qa_clear(names=("rd_qa_focus", "rd_qa_terrain")):
    for name in names:
        ob = bpy.data.objects.get(name)
        if ob is not None:
            me = ob.data
            bpy.data.objects.remove(ob, do_unlink=True)
            if me is not None and me.users == 0:
                bpy.data.meshes.remove(me)


def qa_terrain(cx, cy, half=70.0, step=2.0, name="rd_qa_terrain", drop=0.0, holes=None, hole_vertices=None):
    """Temporary terrain patch (heightmap, Blender coordinates cx, cy) to judge how roads / bridges / portals meet the ground.
    holes: list of oriented rectangles (the `landscape_holes` of the tunnel chunk records) removed from the patch;
    hole_vertices: (n, 2) heightmap vertex indices (make_hole_mask.hole_vertices()), quads with >= 2 such corners are removed
    (use step=1 so the patch grid equals the heightmap grid)."""
    hm = rg.Heightmap(HEIGHTMAP)
    n = int(2 * half / step) + 1
    xs = cx + np.linspace(-half, half, n)
    ys = cy + np.linspace(-half, half, n)
    X, Y = np.meshgrid(xs, ys, indexing="ij")
    Z = hm.z_bl(X, Y) - drop
    ob = bpy.data.objects.get(name)
    if ob is not None:
        me = ob.data
        bpy.data.objects.remove(ob, do_unlink=True)
        if me is not None and me.users == 0:
            bpy.data.meshes.remove(me)
    V = np.stack([X, Y, Z], -1).reshape(-1, 3)
    idx = np.arange(n * n).reshape(n, n)
    F = np.stack([idx[:-1, :-1], idx[1:, :-1], idx[1:, 1:], idx[:-1, 1:]], -1).reshape(-1, 4)
    if holes:
        keep = np.ones(len(F), bool)
        fc = V[F].mean(1)
        for h in holes:
            hx, hy = h["centre_ue_m"][0], -h["centre_ue_m"][1]
            a = math.radians(h["heading_deg"])
            ax, ay = math.cos(a), -math.sin(a)
            dx, dy = fc[:, 0] - hx, fc[:, 1] - hy
            along = dx * ax + dy * ay
            lat = -dx * ay + dy * ax
            keep &= ~((np.abs(along) <= h["length_m"] / 2 + 0.7) & (np.abs(lat) <= h["width_m"] / 2 + 0.7))
        F = F[keep]
    if hole_vertices is not None and len(hole_vertices):
        hv = set(map(tuple, np.asarray(hole_vertices).tolist()))
        gi = np.rint(V[:, 0] + 2016.0).astype(int)
        gj = np.rint(-V[:, 1] + 2016.0).astype(int)
        cnt = np.zeros(len(F), int)
        for k in range(4):
            cnt += np.array([(gi[v], gj[v]) in hv for v in F[:, k]], int)
        F = F[cnt < 2]
    me = bpy.data.meshes.new(name)
    me.from_pydata(V.tolist(), [], F.tolist())
    mat = bpy.data.materials.get("rd_qa_terrain_mat") or bpy.data.materials.new("rd_qa_terrain_mat")
    mat.use_nodes = True
    for nd in mat.node_tree.nodes:
        if nd.type == "BSDF_PRINCIPLED":
            nd.inputs["Base Color"].default_value = (0.20, 0.27, 0.12, 1.0)
            nd.inputs["Roughness"].default_value = 0.95
    me.materials.append(mat)
    me.polygons.foreach_set("use_smooth", np.ones(len(F), bool))
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob
