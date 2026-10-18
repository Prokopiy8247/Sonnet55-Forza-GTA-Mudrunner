# -*- coding: utf-8 -*-
"""
blender_helpers.py  --  MudRunner Unity art pipeline helper library  (Blender 4.2+ / 5.x, tested on 5.2.2 LTS)
=============================================================================================================
Load inside Blender via the MCP (every call; globals persist but reloading is cheap and idempotent):

    exec(open(r"W:\\YouTube\\Claude Sonnet 5.5\\MudRunner\\UnitySonnet5.5MudRunner\\Tools\\blender_helpers.py",
              encoding="utf-8").read())

Contract: Docs/ART_SPEC.md.  1 BU = 1 m, Z up, vehicle FRONT = -Y, LEFT = +X, origin on the ground at the
middle of the wheelbase.  All geometry is built in WORLD coordinates and the object origin is moved
afterwards (finish(origin=...)), so every part can be placed exactly where it belongs (hub centres, spring tops...).

ENABLING PATTERN (work with other asset collections hidden)
    begin_asset("Scout") creates/gets MUDRUNNER_UNITY/<Category>/<Prefix><Name>, MUDRUNNER_UNITY/Collision/COL_<Name>,
    the LOD collections <Name>_LOD1/_LOD2 and the root empty, then calls show_only([...]) which EXCLUDES every other
    collection (other assets, the default 'Collection') from the view layer.  show_all() undoes it, show_lod(ctx, n)
    inspects LOD n.  export_asset() re-enables what it needs and restores the visibility afterwards.

OBJECT NAMING (Blender object names are unique per file, so assets must not share names like Wheel_FL!)
    Every object of an asset is stored in the .blend as  "<Asset>__<ExportName>"  (Scout__Wheel_FL, Scout__COL_Chassis,
    Scout__Wheel_FL_LOD1 ...); only the root empty is called exactly like the asset ("Scout").  export_asset()
    temporarily strips the prefix (objects AND mesh datablocks) so the FBX contains the clean ART_SPEC names
    (Wheel_FL, COL_Chassis, Wheel_FL_LOD1, ...) and then restores them.  Several vehicles / props can live in one
    .blend without ".001" suffixes.  All builders/creators take the CLEAN name and add the prefix themselves.

TYPICAL FLOW  (see BlenderExports/_scratch/scout/*.py for a complete, working example: the Scout)
    A = begin_asset("Scout", category="Vehicles")           # collections, root empty, prefix, isolate the view
    mb = MeshBuilder("Chassis", ["MR_MetalDark"])           # clean export name + material slots (MR_ names)
    mb.box(centre, size); mb.cyl(p0, p1, r0, r1); mb.coil(top, bot, R, wire); mb.tube_path(pts, r, fillet=0.1) ...
    g = mb.mark(); <left side parts>; mb.mirror_x(since=g)  # mirror without negative scales; centre parts afterwards
    obj = mb.finish(A.coll, A.root, origin=(0, 0, 0))       # weld, orient normals, smooth-by-angle, UVs, materials, parent
    make_wheel("Wheel_FL", R=0.40, W=0.235, loc=(0.75, -1.25, 0.40), left=True, parent=A.root, collection=A.coll)
    create_empty("Mount_Spring_Front_L_Top", (x, y, z), parent=A.root, collection=A.coll)
    create_collision_box("COL_Chassis", centre, size, parent=A.root, collection=A.col_coll)
    make_lods(A, ratios=(0.38, 0.14), skip=("COL_", "Wheel_"))   # <Mesh>_LOD1/_LOD2 (Decimate collapse, applied)
    make_wheel("Wheel_FL_LOD1", ..., lod=1, collection=A.lod1)    # wheels/springs are REBUILT at lower detail instead
    validate_asset("Scout", expect=dict(dims=(3.75, 1.80, 1.90), max_objects=60, max_tris=120000))
    bpy.ops.wm.save_mainfile()
    export_asset("Scout", default_export_path("Scout", "Vehicles"))   # or export_asset(["Veh_Scout", "COL_Scout"], path)

API OVERVIEW
  paths/constants ....... PROJECT_ROOT ART_ROOT SCRATCH_DIR MR_TABLE (ART_SPEC section 3, sRGB->linear on creation)
  materials ............. get_material(name) ensure_all_materials()
  collections ........... get_collection ensure_path ensure_file_structure find_layer_collection show_only show_all
                          move_to_collection purge_collection purge_orphans
  assets ................ begin_asset(name, category, clean=False) -> AssetCtx(root, coll, col_coll, lod1, lod2)
                          resolve_asset asset_objects nm() clean_name() default_export_path()
  objects ............... create_empty create_collision_box parent_to apply_transforms set_origin bbox_world tri_count
                          join_objects join_by_material (bmesh based, no selection needed)
  props extras .......... create_collision_hull(verts, faces) create_collision_prism(name, centre, 'X'|'Y'|'Z', length, apothem,
                          sides, radius2) = convex n-gon prism/frustum proxy for logs/barrels/stumps (<= 24 verts, caps
                          fanned so no n-gon > 8)  uv_discs(obj, mat_index) = centred 0..1 disc UVs for every island of a
                          material (cut log ends, stump tops, branch-stub tips); math: exp, log, hypot are imported too
                          (see BlenderExports/_scratch/props/*.py: LogTrailer, Log_Long/Short, Barrel, Crate, Stump)
  mesh builder .......... MeshBuilder: box rbox(rounded box) hexa beam cyl cone sphere torus revolve loft prism grid face
                          coil sweep tube_path | mark mirror_x transform translate | finish(); helpers rounded_path
                          circle_profile rrect_pts(rounded-rect outline) arc_pts(arc in the YZ plane, for wheel arches
                          swept with sweep(..., up=(1,0,0))) triangulate_indices
  wheels ................ make_wheel(): mud-terrain tyre (staggered lugs, sidewall bulge) + rim + spokes + hub + bolts +
                          beadlock bolts as ONE mesh [MR_Rubber, MR_Rim, MR_MetalBright]; lod=1/2 rebuilds it lighter
  shading/UV ............ shade_smooth_by_angle(obj, deg) unwrap(obj, 'box'|'cyl_x'|'cyl_y'|'cyl_z'|'smart')
  LOD ................... decimate_lod make_lods show_lod remove_lods
  QA .................... validate_asset (dims, tris, names, UVs, n-gons, transforms, materials, inverted/inconsistent
                          closed islands) check_vehicle_contract (ART_SPEC 4.x names/markers/hub positions)
                          primitive_check selftest   (selftest builds + exports a throw-away asset and cleans up)
  export ................ export_asset(asset, out_path)  exact ART_SPEC recipe, temp file in BlenderExports/_scratch
                          then shutil.move to the final path

Conventions: builder primitives take WORLD positions; `mat` is a slot index or an MR_ name (added to the slot list on
first use); they return the created BMFaces.  Every closed primitive is born with consistent, outward winding
(primitive_check() proves it) and finish() additionally repairs closed islands (_orient_islands).  UVs: 'box'
projection in metres (1 UV unit = 1 m) for panels, cylindrical for wheels; call unwrap(obj,'smart') for packed islands.
Gotchas: after an object was removed its mesh may stay as orphan data -> purge_orphans(); ear-clipped n-gons give long
sliver triangles on big flat plates (harmless); FBX import of the result into the same .blend creates ".001" names.
"""
import bpy
import bmesh
import math
import os
import re
import shutil
from math import pi, sin, cos, tan, asin, acos, atan2, sqrt, radians, degrees, floor, ceil, exp, log, hypot
from mathutils import Vector, Matrix, Euler, Quaternion

# ----------------------------------------------------------------------------- paths / constants
PROJECT_ROOT = r"W:\YouTube\Claude Sonnet 5.5\MudRunner\UnitySonnet5.5MudRunner"
ART_ROOT = os.path.join(PROJECT_ROOT, "Assets", "Game", "Art")
SCRATCH_DIR = os.path.join(PROJECT_ROOT, "BlenderExports", "_scratch")
TOP_COLLECTION = "MUDRUNNER_UNITY"
CATEGORY_COLLECTIONS = {  # category -> (collection under MUDRUNNER_UNITY, asset collection prefix, art folder)
    "Vehicles": ("Vehicles", "Veh_", "Vehicles"),
    "Trailers": ("Trailers_Cargo", "Trl_", "Trailers"),
    "Cargo": ("Trailers_Cargo", "Cargo_", "Cargo"),
    "Props_Nature": ("Props_Nature", "Nat_", "Props_Nature"),
    "Props_Structures": ("Props_Structures", "Str_", "Props_Structures"),
}

# name: (sRGB base colour, roughness, metallic, extras)   -- ART_SPEC section 3
MR_TABLE = {
    "MR_Paint": ((0.55, 0.42, 0.18), 0.5, 0.1, {}),
    "MR_PaintSecondary": ((0.15, 0.15, 0.15), 0.55, 0.1, {}),
    "MR_MetalDark": ((0.10, 0.10, 0.11), 0.6, 0.8, {}),
    "MR_MetalBright": ((0.55, 0.56, 0.58), 0.35, 1.0, {}),
    "MR_Chrome": ((0.8, 0.8, 0.82), 0.12, 1.0, {}),
    "MR_Rust": ((0.35, 0.17, 0.08), 0.85, 0.4, {}),
    "MR_Rubber": ((0.035, 0.035, 0.035), 0.9, 0.0, {}),
    "MR_Rim": ((0.2, 0.2, 0.2), 0.5, 0.9, {}),
    "MR_Glass": ((0.2, 0.28, 0.3), 0.05, 0.0, {"alpha": 0.35}),
    "MR_LightHead": ((0.95, 0.95, 0.85), 0.1, 0.0, {"emit": 3.0}),
    "MR_LightTail": ((0.8, 0.05, 0.04), 0.2, 0.0, {"emit": 2.0}),
    "MR_LightAmber": ((0.9, 0.5, 0.05), 0.2, 0.0, {"emit": 2.0}),
    "MR_InteriorDark": ((0.08, 0.08, 0.08), 0.8, 0.0, {}),
    "MR_SeatFabric": ((0.14, 0.12, 0.09), 0.95, 0.0, {}),
    "MR_PlasticBlack": ((0.05, 0.05, 0.05), 0.6, 0.0, {}),
    "MR_Cable": ((0.3, 0.3, 0.32), 0.5, 0.9, {}),
    "MR_Wood": ((0.42, 0.28, 0.15), 0.85, 0.0, {}),
    "MR_Bark": ((0.22, 0.15, 0.1), 0.95, 0.0, {}),
    "MR_LogEnd": ((0.55, 0.4, 0.22), 0.9, 0.0, {}),
    "MR_Foliage": ((0.1, 0.25, 0.08), 0.9, 0.0, {}),
    "MR_Rock": ((0.4, 0.39, 0.36), 0.95, 0.0, {}),
    "MR_Moss": ((0.17, 0.27, 0.1), 1.0, 0.0, {}),
    "MR_Concrete": ((0.5, 0.5, 0.48), 0.95, 0.0, {}),
    "MR_RoofMetal": ((0.3, 0.18, 0.12), 0.7, 0.5, {}),
    "MR_Hazard": ((0.9, 0.7, 0.05), 0.6, 0.0, {}),
    "MR_Canvas": ((0.35, 0.38, 0.25), 0.95, 0.0, {}),
    "MR_Sand": ((0.6, 0.52, 0.35), 1.0, 0.0, {}),
}

DEFAULT_NAME_RE = re.compile(
    r"^(Cube|Cylinder|Sphere|Plane|Cone|Circle|Torus|Grid|Icosphere|Monkey|Suzanne|Empty|Mesh|Curve|Text|Light|Camera|"
    r"Collection|Material|Object)(\.\d+)?$")
LOD_RE = re.compile(r"_LOD(\d)$")


def _v(p):
    return p.copy() if isinstance(p, Vector) else Vector(p)


# ----------------------------------------------------------------------------- materials
def _s2l(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def get_material(name):
    """Get or create one of the MR_* materials (Principled BSDF, sRGB table colours converted to linear)."""
    m = bpy.data.materials.get(name)
    if m is not None:
        return m
    if name not in MR_TABLE:
        raise KeyError("Unknown material %r (only ART_SPEC MR_* names are allowed)" % name)
    rgb, rough, metal, extra = MR_TABLE[name]
    m = bpy.data.materials.new(name)
    try:
        m.use_nodes = True
    except Exception:
        pass
    nt = m.node_tree
    bsdf = next((n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED'), None)
    if bsdf is None:
        bsdf = nt.nodes.new('ShaderNodeBsdfPrincipled')
        out = next((n for n in nt.nodes if n.type == 'OUTPUT_MATERIAL'), None) or nt.nodes.new('ShaderNodeOutputMaterial')
        nt.links.new(bsdf.outputs[0], out.inputs[0])
    lin = tuple(_s2l(c) for c in rgb)
    alpha = extra.get("alpha", 1.0)
    bsdf.inputs['Base Color'].default_value = (lin[0], lin[1], lin[2], 1.0)
    bsdf.inputs['Roughness'].default_value = rough
    bsdf.inputs['Metallic'].default_value = metal
    if alpha < 1.0:
        bsdf.inputs['Alpha'].default_value = alpha
        for prop, val in (("surface_render_method", 'BLENDED'), ("blend_method", 'BLEND')):
            try:
                setattr(m, prop, val)
                break
            except Exception:
                pass
    if "emit" in extra:
        for k in ('Emission Color', 'Emission'):
            if k in bsdf.inputs:
                bsdf.inputs[k].default_value = (lin[0], lin[1], lin[2], 1.0)
                break
        if 'Emission Strength' in bsdf.inputs:
            bsdf.inputs['Emission Strength'].default_value = extra["emit"]
    m.diffuse_color = (lin[0], lin[1], lin[2], alpha)
    m.roughness = rough
    m.metallic = metal
    return m


def ensure_all_materials():
    return [get_material(n) for n in MR_TABLE]


def material_names_ok(name):
    return name in MR_TABLE


# ----------------------------------------------------------------------------- collections
def get_collection(name, parent=None):
    """Get or create a collection and make sure it is linked below `parent` (scene collection if None)."""
    c = bpy.data.collections.get(name)
    par = parent or bpy.context.scene.collection
    if c is None:
        c = bpy.data.collections.new(name)
        par.children.link(c)
    elif c.name not in [x.name for x in par.children] and parent is not None:
        try:
            par.children.link(c)
        except RuntimeError:
            pass
    return c


def ensure_path(path):
    """ensure_path("MUDRUNNER_UNITY/Vehicles/Veh_Scout") -> collection (creates the chain)."""
    cur = None
    for part in path.split("/"):
        cur = get_collection(part, cur)
    return cur


def _collection_parent_map(coll=None, parent=None, out=None):
    out = {} if out is None else out
    coll = coll or bpy.context.scene.collection
    for ch in coll.children:
        out[ch.name] = coll.name if coll != bpy.context.scene.collection else None
        _collection_parent_map(ch, coll, out)
    return out


def _descendants(coll):
    res = []
    for ch in coll.children:
        res.append(ch)
        res += _descendants(ch)
    return res


def _iter_layer_collections(lc=None):
    lc = lc or bpy.context.view_layer.layer_collection
    for ch in lc.children:
        yield ch
        yield from _iter_layer_collections(ch)


def find_layer_collection(name):
    for lc in _iter_layer_collections():
        if lc.name == name:
            return lc
    return None


def show_only(names):
    """Enabling pattern: only the given collections (plus their ancestors/descendants) are enabled in the view
    layer; every other collection (other assets, the default 'Collection') is excluded."""
    names = [names] if isinstance(names, str) else list(names)
    pmap = _collection_parent_map()
    keep = set()
    for n in names:
        c = bpy.data.collections.get(n)
        if c is None:
            continue
        keep.add(n)
        for d in _descendants(c):
            keep.add(d.name)
        p = pmap.get(n)
        while p:
            keep.add(p)
            p = pmap.get(p)
    for lc in _iter_layer_collections():
        lc.exclude = lc.name not in keep
        if lc.name in keep:
            lc.hide_viewport = False
            lc.collection.hide_viewport = False
    return sorted(keep)


def show_all():
    for lc in _iter_layer_collections():
        lc.exclude = False
        lc.hide_viewport = False


def move_to_collection(obj, coll):
    for c in list(obj.users_collection):
        c.objects.unlink(obj)
    coll.objects.link(obj)


def purge_collection(coll, recursive=True):
    """Delete all objects (and orphaned meshes) of a collection (rebuild helper)."""
    objs = list(coll.objects)
    if recursive:
        for d in _descendants(coll):
            objs += list(d.objects)
    for o in objs:
        data = o.data
        bpy.data.objects.remove(o, do_unlink=True)
        if isinstance(data, bpy.types.Mesh) and data.users == 0:
            bpy.data.meshes.remove(data)


# ----------------------------------------------------------------------------- asset context / naming
class AssetCtx:
    """Returned by begin_asset(). Holds the root empty, collections and the naming prefix."""

    def __init__(self, name, root, coll, col_coll, lod1, lod2, category):
        self.name, self.root, self.coll, self.col_coll = name, root, coll, col_coll
        self.lod1, self.lod2, self.category = lod1, lod2, category
        self.prefix = name + "__"

    def nm(self, export_name):
        return self.prefix + export_name

    def objects(self):
        return asset_objects(self.root)


ACTIVE = None   # the AssetCtx of the asset currently being built


def nm(export_name):
    """Blender-side name of an export name for the active asset."""
    return (ACTIVE.prefix if ACTIVE else "") + export_name


def clean_name(blender_name, prefix=None):
    p = prefix if prefix is not None else (ACTIVE.prefix if ACTIVE else "")
    return blender_name[len(p):] if p and blender_name.startswith(p) else blender_name


def _claim(name):
    """Remove an existing object/mesh with `name` so a rebuild gets the exact name back."""
    o = bpy.data.objects.get(name)
    if o is not None:
        data = o.data
        bpy.data.objects.remove(o, do_unlink=True)
        if isinstance(data, bpy.types.Mesh) and data.users == 0:
            bpy.data.meshes.remove(data)
    me = bpy.data.meshes.get(name)
    if me is not None and me.users == 0:
        bpy.data.meshes.remove(me)


def ensure_file_structure():
    """MUDRUNNER_UNITY/{Vehicles, Trailers_Cargo, Props_Nature, Props_Structures, Collision} (ART_SPEC section 2)."""
    top = get_collection(TOP_COLLECTION)
    for n in ("Vehicles", "Trailers_Cargo", "Props_Nature", "Props_Structures", "Collision"):
        get_collection(n, top)
    return top


def purge_orphans():
    """Remove unused mesh/curve datablocks left behind by rebuilds (keeps materials)."""
    n = 0
    for me in list(bpy.data.meshes):
        if me.users == 0:
            bpy.data.meshes.remove(me)
            n += 1
    return n


def begin_asset(name, category="Vehicles", clean=False, isolate=True, coll_name=None):
    """Create/get collections MUDRUNNER_UNITY/<Category>/<prefix><name> (+ Collision/COL_<name>, LOD collections),
    the root empty `name`, set the naming prefix and (isolate=True) hide every other asset collection.
    clean=True first deletes everything this asset already contains (full rebuild)."""
    global ACTIVE
    cat_coll, cprefix, _ = CATEGORY_COLLECTIONS[category]
    top = ensure_file_structure()
    cat = get_collection(cat_coll, top)
    coll = get_collection(coll_name or (cprefix + name), cat)
    colroot = get_collection("Collision", top)
    col_coll = get_collection("COL_" + name, colroot)
    lod1 = get_collection(name + "_LOD1", coll)
    lod2 = get_collection(name + "_LOD2", coll)
    if clean:
        purge_collection(coll)
        purge_collection(col_coll)
    root = bpy.data.objects.get(name)
    if root is None:
        root = bpy.data.objects.new(name, None)
        root.empty_display_type = 'PLAIN_AXES'
        root.empty_display_size = 0.25
        coll.objects.link(root)
    ctx = AssetCtx(name, root, coll, col_coll, lod1, lod2, category)
    ACTIVE = ctx
    if isolate:
        show_only([coll.name, col_coll.name])
        lc = find_layer_collection(lod1.name)
        if lc:
            lc.exclude = True
        lc = find_layer_collection(lod2.name)
        if lc:
            lc.exclude = True
    return ctx


def set_active_asset(ctx):
    global ACTIVE
    ACTIVE = ctx
    return ctx


def resolve_asset(asset):
    """asset = root empty (object or name), a collection (object or name) or a list of those ->
    (root_empty, [objects]).  The objects are every given object with all its descendants plus every object inside the
    given collections (recursively).  Lets export_asset / validate_asset accept `"Scout"`, the Scout root object or
    the collections ["Veh_Scout", "COL_Scout"]."""
    items = list(asset) if isinstance(asset, (list, tuple)) else [asset]
    objs, root = [], None
    for it in items:
        if isinstance(it, str):
            o = bpy.data.objects.get(it)
            it = o if o is not None else bpy.data.collections.get(it)
        if isinstance(it, bpy.types.Object):
            if it.type == 'EMPTY' and it.parent is None and root is None:
                root = it
            objs += asset_objects(it)
        elif isinstance(it, bpy.types.Collection):
            for o in it.all_objects:
                objs += asset_objects(o)
        else:
            raise ValueError("cannot resolve asset %r" % (it,))
    seen, res = set(), []
    for o in objs:
        if o.name not in seen:
            seen.add(o.name)
            res.append(o)
    if root is None:
        root = next((o for o in res if o.type == 'EMPTY' and o.parent is None), None)
    if root is None:
        raise ValueError("asset has no root empty")
    return root, res


def asset_objects(root, include_root=True):
    """Root + all descendants (recursive)."""
    root = bpy.data.objects[root] if isinstance(root, str) else root
    res = [root] if include_root else []

    def rec(o):
        for c in o.children:
            res.append(c)
            rec(c)
    rec(root)
    return res


# ----------------------------------------------------------------------------- generic object helpers
def parent_to(obj, parent):
    obj.parent = parent
    obj.matrix_parent_inverse = parent.matrix_world.inverted()
    return obj


def create_empty(name, loc=(0, 0, 0), parent=None, collection=None, display='PLAIN_AXES', size=0.05,
                 rot=None, prefix=True):
    """Plain-axes empty (size 0.05 for markers). `name` is the clean export name."""
    full = nm(name) if prefix else name
    _claim(full)
    e = bpy.data.objects.new(full, None)
    e.empty_display_type = display
    e.empty_display_size = size
    e.location = _v(loc)
    if rot is not None:
        e.rotation_euler = Euler(rot)
    (collection or (ACTIVE.coll if ACTIVE else bpy.context.scene.collection)).objects.link(e)
    if parent is not None:
        parent_to(e, parent)
    return e


def create_collision_box(name, centre, size, parent=None, collection=None, rot=None, prefix=True):
    """8-vertex box mesh, no material, no UVs (collision proxy). Local axes = world axes unless rot given."""
    full = nm(name) if prefix else name
    _claim(full)
    sx, sy, sz = (s / 2.0 for s in size)
    pts = [Vector(p) for p in ((-sx, -sy, -sz), (sx, -sy, -sz), (sx, sy, -sz), (-sx, sy, -sz),
                               (-sx, -sy, sz), (sx, -sy, sz), (sx, sy, sz), (-sx, sy, sz))]
    if rot is not None:
        M = Euler(rot).to_matrix()
        pts = [M @ p for p in pts]
    me = bpy.data.meshes.new(full)
    me.from_pydata([tuple(p) for p in pts], [], [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5),
                                                  (2, 3, 7, 6), (3, 0, 4, 7)])
    me.update()
    o = bpy.data.objects.new(full, me)
    o.location = _v(centre)
    (collection or (ACTIVE.col_coll if ACTIVE else bpy.context.scene.collection)).objects.link(o)
    if parent is not None:
        parent_to(o, parent)
    o.display_type = 'WIRE'
    o.hide_render = True
    return o


def apply_transforms(objs):
    """Bake rotation + scale of mesh objects into their data (location is kept). Negative scale -> normals flipped."""
    for o in objs:
        if o.type != 'MESH':
            continue
        if o.data.users > 1:
            o.data = o.data.copy()
        loc, rot, sca = o.matrix_basis.decompose()
        M = Matrix.LocRotScale(None, rot, sca)
        if abs(sca.x - 1) > 1e-9 or abs(sca.y - 1) > 1e-9 or abs(sca.z - 1) > 1e-9 or rot.angle > 1e-9:
            o.data.transform(M)
            if M.determinant() < 0:
                o.data.flip_normals()
        o.rotation_mode = 'XYZ'
        o.rotation_euler = (0, 0, 0)
        o.scale = (1, 1, 1)
        o.data.update()


def set_origin(obj, world_point):
    """Move the object origin to `world_point` without moving the geometry (object must have identity rot/scale
    and an identity-transform parent)."""
    wp = _v(world_point)
    delta = wp - obj.matrix_world.translation
    obj.data.transform(Matrix.Translation(-delta))
    obj.location = obj.location + delta
    obj.data.update()


def bbox_world(objs):
    mn = Vector((1e9, 1e9, 1e9))
    mx = Vector((-1e9, -1e9, -1e9))
    found = False
    bpy.context.view_layer.update()
    for o in objs:
        if o.type != 'MESH':
            continue
        found = True
        mw = o.matrix_world
        for c in o.bound_box:
            w = mw @ Vector(c)
            for i in range(3):
                mn[i] = min(mn[i], w[i])
                mx[i] = max(mx[i], w[i])
    return (mn, mx) if found else (Vector(), Vector())


def tri_count(obj):
    me = obj.data
    return sum(len(p.vertices) - 2 for p in me.polygons)


def join_objects(objs, name, collection=None, parent=None, origin=(0, 0, 0), smooth=40.0, prefix=True):
    """Join mesh objects (any transforms) into ONE new object `name` (originals removed). Material slots are merged
    by material name. Done with bmesh (no operators, no selection needed)."""
    objs = [o for o in objs if o.type == 'MESH']
    full = nm(name) if prefix else name
    mats = []
    for o in objs:
        for s in o.material_slots:
            if s.material and s.material.name not in mats:
                mats.append(s.material.name)
    bm = bmesh.new()
    uvname = None
    for o in objs:
        tmp = bmesh.new()
        tmp.from_mesh(o.data)
        tmp.transform(o.matrix_world)
        slot_map = [mats.index(s.material.name) if s.material else 0 for s in o.material_slots] or [0]
        for f in tmp.faces:
            f.material_index = slot_map[min(f.material_index, len(slot_map) - 1)]
        me_tmp = bpy.data.meshes.new("__tmp_join")
        tmp.to_mesh(me_tmp)
        tmp.free()
        bm.from_mesh(me_tmp)
        bpy.data.meshes.remove(me_tmp)
    origin = _v(origin)
    bmesh.ops.translate(bm, verts=bm.verts, vec=-origin)
    _orient_islands(bm)
    if smooth:
        _shade_bm(bm, smooth)
    for o in objs:                       # remove the sources first (one of them may already carry the target name)
        data = o.data
        bpy.data.objects.remove(o, do_unlink=True)
        if data.users == 0:
            bpy.data.meshes.remove(data)
    _claim(full)
    me = bpy.data.meshes.new(full)
    bm.to_mesh(me)
    bm.free()
    for mname in mats:
        me.materials.append(get_material(mname))
    obj = bpy.data.objects.new(full, me)
    obj.location = origin
    (collection or (ACTIVE.coll if ACTIVE else bpy.context.scene.collection)).objects.link(obj)
    if parent is not None:
        parent_to(obj, parent)
    return obj


def join_by_material(objs, name_fmt="{asset}_{mat}", collection=None, parent=None, origin=(0, 0, 0)):
    """Group single-material mesh objects by material and join each group. name_fmt placeholders: {mat} (without
    MR_), {asset}. Returns the list of new objects."""
    groups = {}
    for o in objs:
        if o.type != 'MESH':
            continue
        key = tuple(sorted(s.material.name for s in o.material_slots if s.material)) or ("none",)
        groups.setdefault(key, []).append(o)
    out = []
    for key, lst in groups.items():
        mat = "_".join(k.replace("MR_", "") for k in key)
        out.append(join_objects(lst, name_fmt.format(mat=mat, asset=(ACTIVE.name if ACTIVE else "Asset")),
                                collection, parent, origin))
    return out


# ----------------------------------------------------------------------------- geometry helpers
def axis_basis(axis, up=None):
    """Right-handed orthonormal basis (u, w, a) with a = axis direction."""
    a = _v(axis)
    if a.length < 1e-9:
        a = Vector((0, 0, 1))
    a.normalize()
    cands = []
    if up is not None:
        cands.append(_v(up))
    cands += [Vector((0, 0, 1)), Vector((1, 0, 0)), Vector((0, 1, 0))]
    for c in cands:
        u = c - a * c.dot(a)
        if u.length > 1e-4:
            u.normalize()
            return u, a.cross(u), a
    raise ValueError("degenerate axis")


def _newell(pts):
    n = Vector()
    k = len(pts)
    for i in range(k):
        a, b = pts[i], pts[(i + 1) % k]
        n.x += (a.y - b.y) * (a.z + b.z)
        n.y += (a.z - b.z) * (a.x + b.x)
        n.z += (a.x - b.x) * (a.y + b.y)
    return n


def _pt_in_tri(p, a, b, c):
    def sgn(p1, p2, p3):
        return (p1[0] - p3[0]) * (p2[1] - p3[1]) - (p2[0] - p3[0]) * (p1[1] - p3[1])
    d1, d2, d3 = sgn(p, a, b), sgn(p, b, c), sgn(p, c, a)
    neg = (d1 < -1e-12) or (d2 < -1e-12) or (d3 < -1e-12)
    pos = (d1 > 1e-12) or (d2 > 1e-12) or (d3 > 1e-12)
    return not (neg and pos)


def triangulate_indices(pts):
    """Ear-clipping triangulation of a (nearly) planar polygon given as Vectors -> list of index triples."""
    n = len(pts)
    if n < 3:
        return []
    if n == 3:
        return [(0, 1, 2)]
    nrm = _newell(pts)
    if nrm.length < 1e-14:
        return [(0, k, k + 1) for k in range(1, n - 1)]
    drop = max(range(3), key=lambda i: abs(nrm[i]))
    ix = [i for i in range(3) if i != drop]
    p2 = [(p[ix[0]], p[ix[1]]) for p in pts]
    area = sum(p2[i][0] * p2[(i + 1) % n][1] - p2[(i + 1) % n][0] * p2[i][1] for i in range(n))
    order = list(range(n))
    rev = area < 0
    if rev:
        order.reverse()
    tris = []
    guard = 0
    while len(order) > 3 and guard < 5000:
        guard += 1
        found = False
        m = len(order)
        for k in range(m):
            i0, i1, i2 = order[k - 1], order[k], order[(k + 1) % m]
            a, b, c = p2[i0], p2[i1], p2[i2]
            cr = (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])
            if cr <= 1e-14:
                continue
            ok = True
            for j in order:
                if j in (i0, i1, i2):
                    continue
                if _pt_in_tri(p2[j], a, b, c):
                    ok = False
                    break
            if ok:
                tris.append((i0, i1, i2))
                order.pop(k)
                found = True
                break
        if not found:
            break
    if len(order) == 3:
        tris.append(tuple(order))
    else:
        for k in range(1, len(order) - 1):
            tris.append((order[0], order[k], order[k + 1]))
    if rev:      # we clipped on the reversed polygon -> restore the winding of the input polygon
        tris = [(a, c, b) for (a, b, c) in tris]
    return tris


def circle_profile(r, segs=8, ry=None, start=0.0):
    ry = r if ry is None else ry
    return [(r * cos(start + 2 * pi * i / segs), ry * sin(start + 2 * pi * i / segs)) for i in range(segs)]


def rrect_pts(hx, hz, r, steps=3):
    """Outline of a rounded rectangle (half extents hx, hz; corner radius r) as (x, z) tuples, 4*(steps+1) points."""
    r = max(0.0, min(r, hx, hz))
    pts = []
    for cx, cz, a0 in ((hx - r, hz - r, 0.0), (-(hx - r), hz - r, 90.0), (-(hx - r), -(hz - r), 180.0),
                       (hx - r, -(hz - r), 270.0)):
        for k in range(steps + 1):
            a = radians(a0 + 90.0 * k / steps)
            pts.append((cx + r * cos(a), cz + r * sin(a)))
    return pts


def arc_pts(cy, cz, r, a0_deg, a1_deg, n=16, x=0.0):
    """Points on a circle in the YZ plane (centre y=cy, z=cz) as Vectors (x, y, z). Angle 0 = straight up (+Z),
    +90 = toward +Y (rear), -90 = toward -Y (front)."""
    out = []
    for i in range(n + 1):
        a = radians(a0_deg + (a1_deg - a0_deg) * i / n)
        out.append(Vector((x, cy + r * sin(a), cz + r * cos(a))))
    return out


def rounded_path(pts, radius, steps=4):
    """Polyline with filleted corners (radius in metres, auto-limited by segment length)."""
    pts = [_v(p) for p in pts]
    if len(pts) < 3 or radius <= 0:
        return pts
    out = [pts[0]]
    for i in range(1, len(pts) - 1):
        p0, p1, p2 = pts[i - 1], pts[i], pts[i + 1]
        d1 = (p1 - p0)
        d2 = (p2 - p1)
        l1, l2 = d1.length, d2.length
        if l1 < 1e-9 or l2 < 1e-9:
            out.append(p1)
            continue
        d1 = d1 / l1
        d2 = d2 / l2
        cphi = max(-1.0, min(1.0, d1.dot(d2)))
        phi = math.acos(cphi)
        if phi < 1e-3:
            out.append(p1)
            continue
        r = radius
        t = r * math.tan(phi / 2)
        tmax = 0.5 * min(l1, l2)
        if t > tmax:
            r = r * tmax / t
            t = tmax
        A = p1 - d1 * t
        n = (d2 - d1 * cphi)
        n.normalize()
        centre = A + n * r
        for s in range(steps + 1):
            psi = phi * s / steps
            out.append(centre - n * (r * cos(psi)) + d1 * (r * sin(psi)))
    out.append(pts[-1])
    return out


def _signed_volume(faces):
    vol = 0.0
    for f in faces:
        vs = [l.vert.co for l in f.loops]
        for i in range(1, len(vs) - 1):
            vol += vs[0].dot(vs[i].cross(vs[i + 1]))
    return vol / 6.0


# ----------------------------------------------------------------------------- closed-island orientation fixer
def _islands(bm):
    """Edge-connected face islands -> list of (faces, closed_manifold, consistent_winding)."""
    bm.faces.index_update()
    seen = set()
    out = []
    for f in list(bm.faces):
        if f.index in seen:
            continue
        stack = [f]
        isl = []
        closed = True
        consistent = True
        seen.add(f.index)
        while stack:
            cur = stack.pop()
            isl.append(cur)
            for e in cur.edges:
                lf = e.link_faces
                if len(lf) != 2:
                    closed = False
                    continue
                ll = e.link_loops
                if len(ll) == 2 and ll[0].vert == ll[1].vert:
                    consistent = False
                for nf in lf:
                    if nf.index not in seen:
                        seen.add(nf.index)
                        stack.append(nf)
        out.append((isl, closed, consistent))
    return out


def _orient_islands(bm):
    """Make every closed manifold island consistent and outward (signed volume > 0). Returns number fixed."""
    fixed = 0
    for isl, closed, consistent in _islands(bm):
        if not closed or len(isl) < 4:
            continue
        if not consistent:
            bmesh.ops.recalc_face_normals(bm, faces=isl)
            fixed += 1
        elif _signed_volume(isl) < 0:
            bmesh.ops.reverse_faces(bm, faces=isl)
            fixed += 1
    return fixed


# ----------------------------------------------------------------------------- smoothing / UV on bmesh
def _shade_bm(bm, angle_deg=40.0):
    """Smooth faces + sharp edges where the face angle exceeds angle_deg ('shade smooth by angle')."""
    ang = radians(angle_deg)
    bm.normal_update()
    for f in bm.faces:
        f.smooth = True
    for e in bm.edges:
        nf = len(e.link_faces)
        if nf == 2:
            e.smooth = e.calc_face_angle(0.0) <= ang
        elif nf > 2:
            e.smooth = False


def shade_smooth_by_angle(obj, angle_deg=40.0):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    _shade_bm(bm, angle_deg)
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()


def _uv_layer(bm):
    return bm.loops.layers.uv.get("UVMap") or bm.loops.layers.uv.new("UVMap")


def _uv_box(bm, scale=1.0):
    uv = _uv_layer(bm)
    bm.normal_update()
    for f in bm.faces:
        n = f.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        sg = 1.0 if n[ax] >= 0 else -1.0
        for l in f.loops:
            p = l.vert.co
            if ax == 0:
                u, v = -sg * p.y, p.z
            elif ax == 1:
                u, v = sg * p.x, p.z
            else:
                u, v = p.x, sg * p.y
            l[uv].uv = (u / scale, v / scale)


def _uv_cyl(bm, axis='X', scale=1.0):
    """Cylindrical projection about a local axis through the origin; axial faces use planar projection."""
    uv = _uv_layer(bm)
    bm.normal_update()
    ai = {'X': 0, 'Y': 1, 'Z': 2}[axis]
    o1, o2 = [i for i in range(3) if i != ai]
    for f in bm.faces:
        n = f.normal
        axial = abs(n[ai]) > 0.7
        rs = [sqrt(l.vert.co[o1] ** 2 + l.vert.co[o2] ** 2) for l in f.loops]
        rref = max(sum(rs) / len(rs), 1e-4)
        th0 = None
        for l in f.loops:
            p = l.vert.co
            if axial:
                sg = 1.0 if n[ai] >= 0 else -1.0
                l[uv].uv = (sg * p[o1] / scale, p[o2] / scale)
            else:
                th = atan2(p[o2], p[o1])
                if th0 is None:
                    th0 = th
                d = th - th0
                while d > pi:
                    d -= 2 * pi
                while d < -pi:
                    d += 2 * pi
                l[uv].uv = ((th0 + d) * max(rref, 0.05) / scale, p[ai] / scale)
        if not axial:
            # radial faces (planes through the axis) collapse under the cylindrical map -> use a planar fallback
            uvs = [l[uv].uv for l in f.loops]
            ar = 0.0
            for i in range(1, len(uvs) - 1):
                ar += abs((uvs[i][0] - uvs[0][0]) * (uvs[i + 1][1] - uvs[0][1])
                          - (uvs[i][1] - uvs[0][1]) * (uvs[i + 1][0] - uvs[0][0])) * 0.5
            if ar < 0.15 * f.calc_area() / (scale * scale):
                c = f.calc_center_median()
                rad = Vector((0, 0, 0))
                rad[o1], rad[o2] = c[o1], c[o2]
                if rad.length < 1e-6:
                    rad[o1] = 1.0
                rad.normalize()
                for l in f.loops:
                    # planar map onto the plane through the axis and the face's radial direction
                    l[uv].uv = (l.vert.co.dot(rad) / scale, l.vert.co[ai] / scale)


def unwrap(obj, method='box', scale=1.0, angle_limit=66.0, margin=0.02):
    """UV-unwrap a mesh object. 'box' (default, world-metre texel density), 'cyl_x/y/z' or 'smart'
    (bpy.ops.uv.smart_project - islands packed to 0..1, density not metric)."""
    if method == 'smart':
        prev = bpy.context.view_layer.objects.active
        for o in bpy.context.selected_objects:
            o.select_set(False)
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.mode_set(mode='EDIT')
        bpy.ops.mesh.select_all(action='SELECT')
        bpy.ops.uv.smart_project(angle_limit=radians(angle_limit), island_margin=margin)
        bpy.ops.object.mode_set(mode='OBJECT')
        obj.select_set(False)
        if prev:
            bpy.context.view_layer.objects.active = prev
        return obj
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    if method == 'box':
        _uv_box(bm, scale)
    else:
        _uv_cyl(bm, method[-1].upper(), scale)
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()
    return obj


# ----------------------------------------------------------------------------- MeshBuilder
class MeshBuilder:
    """Accumulates world-space geometry in a bmesh with named MR_ material slots; finish() creates the object."""

    def __init__(self, name, materials=()):
        self.name = name
        self.materials = list(materials)
        self.bm = bmesh.new()
        self._grp = self.bm.faces.layers.int.new("_grp")
        self.group = 0

    # -- bookkeeping -------------------------------------------------------------------------
    def mat(self, m):
        if isinstance(m, int):
            while len(self.materials) <= m:
                self.materials.append("MR_MetalDark")
            return m
        if m not in self.materials:
            self.materials.append(m)
        return self.materials.index(m)

    def mark(self):
        """Start a new group; returns its id (use with mirror_x(since=id) / transform(since=id))."""
        self.group += 1
        return self.group

    def _f(self, vs, mat):
        try:
            f = self.bm.faces.new(vs)
        except ValueError:
            return None
        f.material_index = mat
        f[self._grp] = self.group
        return f

    def _vert(self, co):
        return self.bm.verts.new(co)

    def _close(self, faces):
        faces = [f for f in faces if f is not None]
        if faces and _signed_volume(faces) < 0:
            for f in faces:
                f.normal_flip()
        return faces

    def _cap(self, verts, mat):
        pts = [v.co.copy() for v in verts]
        out = []
        for (i, j, k) in triangulate_indices(pts):
            f = self._f([verts[i], verts[j], verts[k]], mat)
            if f:
                out.append(f)
        return out

    # -- primitives --------------------------------------------------------------------------
    def face(self, pts, mat=0):
        """Single free polygon (tri/quad/n-gon<=8; larger polygons are ear-clipped)."""
        mat = self.mat(mat)
        vs = [self._vert(_v(p)) for p in pts]
        if len(vs) <= 4:
            f = self._f(vs, mat)
            return [f] if f else []
        return self._cap(vs, mat)

    def hexa(self, p, mat=0):
        """Hexahedron from 8 corners: p[0..3] one quad loop, p[4..7] the opposite loop (p[i+4] opposite p[i])."""
        mat = self.mat(mat)
        vs = [self._vert(_v(q)) for q in p]
        quads = [(0, 1, 2, 3), (4, 7, 6, 5), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)]
        faces = [self._f([vs[i] for i in q], mat) for q in quads]
        return self._close(faces)

    def box(self, centre, size, rot=None, mat=0):
        """Axis-aligned (or rot=Euler/Matrix/Quaternion rotated) box."""
        sx, sy, sz = (s / 2.0 for s in size)
        loc = [Vector(q) for q in ((-sx, -sy, -sz), (sx, -sy, -sz), (sx, sy, -sz), (-sx, sy, -sz),
                                   (-sx, -sy, sz), (sx, -sy, sz), (sx, sy, sz), (-sx, sy, sz))]
        if rot is not None:
            if isinstance(rot, (Matrix,)):
                M = rot.to_3x3()
            elif isinstance(rot, Quaternion):
                M = rot.to_matrix()
            else:
                M = Euler(rot).to_matrix()
            loc = [M @ q for q in loc]
        c = _v(centre)
        return self.hexa([c + q for q in loc], mat)

    def beam(self, p0, p1, w, h, up=(0, 0, 1), mat=0, w1=None, h1=None):
        """Box from p0 to p1 with cross-section w (sideways) x h (along `up`); optional end section w1 x h1 (taper)."""
        p0, p1 = _v(p0), _v(p1)
        d = p1 - p0
        u, s, a = axis_basis(d, up)   # u ~ up, s = a x u (sideways)
        w1 = w if w1 is None else w1
        h1 = h if h1 is None else h1
        pts = []
        for p, ww, hh in ((p0, w, h), (p1, w1, h1)):
            pts.append([p + s * (-ww / 2) + u * (-hh / 2), p + s * (ww / 2) + u * (-hh / 2),
                        p + s * (ww / 2) + u * (hh / 2), p + s * (-ww / 2) + u * (hh / 2)])
        return self.hexa(pts[0] + pts[1], mat)

    def rbox(self, centre, size, r=0.03, steps=2, mat=0, rot=None):
        """Box with all 12 edges rounded (radius r, `steps` segments per corner) -- body panels, bumpers, hoods.
        Built as a loft of rounded-rectangle sections along local Y (end caps are flat). Outward winding guaranteed."""
        mat = self.mat(mat)
        hx, hy, hz = (s / 2.0 for s in size)
        r = max(1e-4, min(r, hx * 0.999, hy * 0.999, hz * 0.999))
        ph = [(pi / 2.0) * k / (steps + 0.35) for k in range(steps + 1)]      # 0 .. just below 90 deg
        secs = []                                                             # (y_offset_from_inner_end, corner radius)
        for k, p_ in enumerate(ph):
            u = r * sin(p_)
            rho = r * cos(p_)
            if k == len(ph) - 1:
                u = r
            secs.append((u, max(rho, 0.0015)))
        if rot is not None:
            if isinstance(rot, Matrix):
                M = rot.to_3x3()
            elif isinstance(rot, Quaternion):
                M = rot.to_matrix()
            else:
                M = Euler(rot).to_matrix()
        else:
            M = None
        c = _v(centre)
        yi = hy - r
        order = [(-1, k) for k in range(len(secs) - 1, -1, -1)]
        if yi > 1e-6:
            order += [(+1, k) for k in range(len(secs))]
        else:
            order += [(+1, k) for k in range(1, len(secs))]
        rings = []
        for sg, k in order:
            u, rho = secs[k]
            yy = sg * (yi + u)
            ring = []
            for (px, pz) in rrect_pts(hx - r + rho, hz - r + rho, rho, steps):
                q = Vector((px, yy, pz))
                if M is not None:
                    q = M @ q
                ring.append(c + q)
            rings.append(ring)
        return self.loft(rings, mat, True, True, True)

    def cyl(self, p0, p1, r0, r1=None, segs=12, mat=0, caps=(True, True), up=None, phase=0.0):
        """Cylinder / cone frustum from p0 (radius r0) to p1 (radius r1). r=0 gives an apex."""
        p0, p1 = _v(p0), _v(p1)
        r1 = r0 if r1 is None else r1
        mat = self.mat(mat)
        u, w, a = axis_basis(p1 - p0, up)
        ang = [phase + 2 * pi * i / segs for i in range(segs)]

        def ring(c, r):
            if r < 1e-9:
                return [self._vert(c)] * segs
            return [self._vert(c + (u * cos(t) + w * sin(t)) * r) for t in ang]
        A, B = ring(p0, r0), ring(p1, r1)
        faces = []
        for i in range(segs):
            j = (i + 1) % segs
            if r0 < 1e-9:
                faces.append(self._f([A[0], B[j], B[i]], mat))
            elif r1 < 1e-9:
                faces.append(self._f([A[i], A[j], B[0]], mat))
            else:
                faces.append(self._f([A[i], A[j], B[j], B[i]], mat))
        for ring_, c, on, r, flip in ((A, p0, caps[0], r0, True), (B, p1, caps[1], r1, False)):
            if on and r > 1e-9:
                cv = self._vert(c)
                for i in range(segs):
                    a_, b_ = ring_[i], ring_[(i + 1) % segs]
                    faces.append(self._f([cv, b_, a_] if flip else [cv, a_, b_], mat))
        return self._close(faces)

    def cone(self, p0, p1, r0, segs=12, mat=0, up=None):
        return self.cyl(p0, p1, r0, 0.0, segs, mat, (True, False), up)

    def revolve(self, profile, p0, p1, segs=16, mat=0, cap_start=True, cap_end=True, loop=False, up=None, phase=0.0):
        """Lathe: profile = [(t, r), ...] t = distance along p0->p1, r = radius. loop=True joins last->first profile
        point (closed profile => closed solid of revolution, no caps). r=0 points collapse to an apex."""
        p0, p1 = _v(p0), _v(p1)
        mat = self.mat(mat)
        u, w, a = axis_basis(p1 - p0, up)
        ang = [phase + 2 * pi * i / segs for i in range(segs)]
        rings = []
        for (t, r) in profile:
            c = p0 + a * t
            if r < 1e-9:
                rings.append(([self._vert(c)] * segs, True))
            else:
                rings.append(([self._vert(c + (u * cos(x) + w * sin(x)) * r) for x in ang], False))
        faces = []
        n = len(rings)
        pairs = [(i, i + 1) for i in range(n - 1)] + ([(n - 1, 0)] if loop else [])
        for i, j in pairs:
            (A, da), (B, db) = rings[i], rings[j]
            for k in range(segs):
                k2 = (k + 1) % segs
                if da and db:
                    continue
                if da:
                    faces.append(self._f([A[0], B[k2], B[k]], mat))
                elif db:
                    faces.append(self._f([A[k], A[k2], B[0]], mat))
                else:
                    faces.append(self._f([A[k], A[k2], B[k2], B[k]], mat))
        if not loop:
            for idx, on in ((0, cap_start), (n - 1, cap_end)):
                ring_, degen = rings[idx]
                if on and not degen:
                    c = p0 + a * profile[idx][0]
                    cv = self._vert(c)
                    for k in range(segs):
                        a_, b_ = ring_[k], ring_[(k + 1) % segs]
                        faces.append(self._f([cv, b_, a_] if idx == 0 else [cv, a_, b_], mat))
        return self._close(faces) if (loop or (cap_start and cap_end)) else [f for f in faces if f]

    def sphere(self, c, r, segs=12, rings=8, mat=0, axis=(0, 0, 1)):
        """UV sphere of radius r at c (poles along `axis`)."""
        c = _v(c)
        a = _v(axis).normalized()
        prof = [(r * (1 - cos(pi * i / rings)), r * sin(pi * i / rings)) for i in range(rings + 1)]
        return self.revolve(prof, c - a * r, c + a * r, segs=segs, mat=mat)

    def torus(self, c, axis, R, r, major=24, minor=8, mat=0, up=None):
        """Torus (steering wheel rim, rings, hoops). axis = normal of the ring plane."""
        c = _v(c)
        u, w, a = axis_basis(axis, up)
        rings = []
        for k in range(major + 1):
            t = 2 * pi * (k % major) / major
            rad = u * cos(t) + w * sin(t)
            cc = c + rad * R
            rings.append([cc + (rad * cos(2 * pi * j / minor) + a * sin(2 * pi * j / minor)) * r for j in range(minor)])
        return self._close(self.loft(rings, mat, True, False, False))

    def loft(self, rings, mat=0, closed_ring=True, cap_start=False, cap_end=False):
        """Bridge consecutive rings (lists of equal length of points)."""
        mat = self.mat(mat)
        R = [[self._vert(_v(p)) for p in ring] for ring in rings]
        n = len(R[0])
        faces = []
        for i in range(len(R) - 1):
            for k in range(n if closed_ring else n - 1):
                k2 = (k + 1) % n
                faces.append(self._f([R[i][k], R[i][k2], R[i + 1][k2], R[i + 1][k]], mat))
        if cap_start:
            faces += self._cap(R[0][::-1], mat)
        if cap_end:
            faces += self._cap(R[-1], mat)
        if cap_start and cap_end:
            return self._close(faces)
        return [f for f in faces if f]

    def prism(self, pts2d, plane, a0, a1, mat=0):
        """Extrude a closed 2D polygon. plane 'YZ' -> polygon coords (y,z) extruded along X from a0 to a1;
        'XZ' -> (x,z) along Y;  'XY' -> (x,y) along Z."""
        mat = self.mat(mat)

        def P(a, q):
            if plane == 'YZ':
                return Vector((a, q[0], q[1]))
            if plane == 'XZ':
                return Vector((q[0], a, q[1]))
            return Vector((q[0], q[1], a))
        A = [self._vert(P(a0, q)) for q in pts2d]
        B = [self._vert(P(a1, q)) for q in pts2d]
        n = len(A)
        faces = [self._f([A[i], A[(i + 1) % n], B[(i + 1) % n], B[i]], mat) for i in range(n)]
        faces += self._cap(A[::-1], mat)
        faces += self._cap(B, mat)
        return self._close(faces)

    def grid(self, origin, du, dv, nu, nv, fn=None, mat=0):
        """Open (nu x nv) quad grid spanning origin + i*du + j*dv; fn(i,j,pos)->pos can displace points."""
        mat = self.mat(mat)
        o, du, dv = _v(origin), _v(du), _v(dv)
        V = [[None] * (nv + 1) for _ in range(nu + 1)]
        for i in range(nu + 1):
            for j in range(nv + 1):
                p = o + du * (i / nu) + dv * (j / nv)
                V[i][j] = self._vert(fn(i, j, p) if fn else p)
        faces = []
        for i in range(nu):
            for j in range(nv):
                faces.append(self._f([V[i][j], V[i + 1][j], V[i + 1][j + 1], V[i][j + 1]], mat))
        return [f for f in faces if f]

    def coil(self, p0, p1, radius, wire, turns=7.0, per_turn=14, wire_segs=6, mat=0, flat_end_turns=0.9, up=None):
        """Real helical coil spring from p0 (upper end) to p1 with `turns` active+ground turns."""
        p0, p1 = _v(p0), _v(p1)
        mat = self.mat(mat)
        u, w, a = axis_basis(p1 - p0, up)
        L = (p1 - p0).length
        end_t = min(flat_end_turns, turns / 2.0 - 0.25)
        mid_t = turns - 2 * end_t
        h_end = end_t * wire * 2.1
        h_mid = max(L - 2 * wire - 2 * h_end, 0.01)

        def height(tt):
            if tt <= end_t:
                return wire + tt * (h_end / end_t)
            if tt >= turns - end_t:
                return wire + h_end + h_mid + (tt - (turns - end_t)) * (h_end / end_t)
            return wire + h_end + (tt - end_t) * (h_mid / mid_t)

        def dh(tt):
            if tt <= end_t or tt >= turns - end_t:
                return h_end / end_t
            return h_mid / mid_t
        N = int(turns * per_turn)
        rings = []
        for s in range(N + 1):
            tt = turns * s / N
            ang = 2 * pi * tt
            rad = u * cos(ang) + w * sin(ang)
            tang = (-u * sin(ang) + w * cos(ang)) * (radius * 2 * pi) + a * dh(tt)
            tang.normalize()
            c = p0 + a * height(tt) + rad * radius
            e2 = tang.cross(rad)
            e2.normalize()
            rings.append([c + (rad * cos(2 * pi * k / wire_segs) + e2 * sin(2 * pi * k / wire_segs)) * wire
                          for k in range(wire_segs)])
        return self.loft(rings, mat, True, True, True)

    def sweep(self, path, profile, mat=0, up=None, caps=True, scales=None):
        """Sweep a closed 2D profile [(a,b),...] along a polyline path using parallel-transport frames.
        Local frame per point: a -> N (starts as `up` projected), b -> T x N."""
        mat = self.mat(mat)
        pts = [_v(p) for p in path]
        n = len(pts)
        tang = []
        for i in range(n):
            if i == 0:
                t = pts[1] - pts[0]
            elif i == n - 1:
                t = pts[-1] - pts[-2]
            else:
                t = (pts[i + 1] - pts[i]).normalized() + (pts[i] - pts[i - 1]).normalized()
            t.normalize()
            tang.append(t)
        u0, _, _ = axis_basis(tang[0], up)
        N = u0
        prev = tang[0]
        rings = []
        for i in range(n):
            t = tang[i]
            if i > 0:
                q = prev.rotation_difference(t)
                N = q @ N
                N = N - t * N.dot(t)
                N.normalize()
            B = t.cross(N)
            s = scales[i] if scales else 1.0
            rings.append([pts[i] + N * (a * s) + B * (b * s) for (a, b) in profile])
            prev = t
        return self.loft(rings, mat, True, caps, caps)

    def tube_path(self, pts, radius, segs=8, fillet=0.0, steps=4, mat=0, up=None, caps=True):
        """Round tube along a polyline, optionally with filleted bends (roll cage, bull bar, snorkel...)."""
        path = rounded_path(pts, fillet, steps) if fillet > 0 else [_v(p) for p in pts]
        return self.sweep(path, circle_profile(radius, segs), mat, up, caps)

    # -- editing -----------------------------------------------------------------------------
    def transform(self, M, since=None):
        if since is None:
            verts = list(self.bm.verts)
        else:
            vs = set()
            for f in self.bm.faces:
                if f[self._grp] >= since:
                    vs.update(f.verts)
            verts = list(vs)
        bmesh.ops.transform(self.bm, matrix=M, verts=verts)

    def translate(self, v, since=None):
        self.transform(Matrix.Translation(_v(v)), since)

    def mirror_x(self, since=0):
        """Mirror all faces of groups >= since across x=0 (new faces, normals kept outward). Call mark() before the
        left-side parts, then mirror_x(since=mark). Coincident vertices on x=0 are welded in finish()."""
        faces = [f for f in self.bm.faces if f[self._grp] >= since]
        self.mark()
        vmap = {}
        for f in faces:
            vs = []
            for l in f.loops:
                v = l.vert
                if v not in vmap:
                    vmap[v] = self._vert((-v.co.x, v.co.y, v.co.z))
                vs.append(vmap[v])
            vs.reverse()
            self._f(vs, f.material_index)

    def stats(self):
        return len(self.bm.verts), len(self.bm.faces)

    # -- output ------------------------------------------------------------------------------
    def finish(self, collection=None, parent=None, origin=(0, 0, 0), smooth=40.0, uv='box', uv_scale=1.0,
               merge=1e-5, prefix=True, hide=False):
        """Create the mesh object. origin = world point that becomes the object origin. uv: 'box'|'cyl_x'|'cyl_y'|
        'cyl_z'|None. smooth: degrees for shade-smooth-by-angle (None = flat)."""
        bm = self.bm
        full = nm(self.name) if prefix else self.name
        bm.faces.layers.int.remove(self._grp)
        if merge:
            bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=merge)
        origin = _v(origin)
        if origin.length > 0:
            bmesh.ops.translate(bm, verts=bm.verts, vec=-origin)
        self.orient_fixed = _orient_islands(bm)
        bm.normal_update()
        if smooth:
            _shade_bm(bm, smooth)
        if uv == 'box':
            _uv_box(bm, uv_scale)
        elif uv and uv.startswith('cyl_'):
            _uv_cyl(bm, uv[-1].upper(), uv_scale)
        _claim(full)
        me = bpy.data.meshes.new(full)
        bm.to_mesh(me)
        bm.free()
        for m in self.materials:
            me.materials.append(get_material(m))
        me.update()
        obj = bpy.data.objects.new(full, me)
        obj.location = origin
        (collection or (ACTIVE.coll if ACTIVE else bpy.context.scene.collection)).objects.link(obj)
        if parent is not None:
            parent_to(obj, parent)
        if hide:
            obj.hide_viewport = True
        return obj


# ----------------------------------------------------------------------------- wheel builder
def make_wheel(name, R=0.40, W=0.235, loc=(0, 0, 0), left=True, rim_r=None, lugs=32, lug_h=None,
               spokes=6, bolts=6, beadlock=12, rot_z_deg=0.0, parent=None, collection=None, origin=None,
               segs=64, lod=0):
    """Mud-terrain wheel as ONE mesh: slots [MR_Rubber, MR_Rim, MR_MetalBright]. Hub centre = object origin,
    axle along X, outer rim face toward +X (left=True) or -X (left=False: built then rotated 180 deg about Z,
    never mirrored). `rot_z_deg` rotates the finished wheel about Z (spare wheel: 90 -> axle along Y, outer face
    toward +Y). Tyre: sidewall bulge, `lugs` staggered tread positions x 4 blocks (shoulder + centre lugs).
    lod=1/2 rebuilds the wheel with fewer segments/lugs (pass the _LOD1/_LOD2 name) instead of decimating."""
    rim_r = rim_r if rim_r is not None else 0.5 * R
    lug_h = lug_h if lug_h is not None else 0.0625 * R
    if lod == 1:
        segs, lugs, beadlock = min(segs, 32), max(10, int(lugs * 0.4)), 0
    elif lod >= 2:
        segs, lugs, beadlock, bolts, spokes = 24, 0, 0, 0, max(4, spokes - 2)
    hw = W / 2.0
    rb = R - lug_h if lugs else R - 0.5 * lug_h   # tyre base radius under the lugs
    H = rb - rim_r                       # sidewall height
    mb = MeshBuilder(name, ["MR_Rubber", "MR_Rim", "MR_MetalBright"])
    X0, X1 = Vector((0, 0, 0)), Vector((1, 0, 0))
    # outer path of the tyre (x, r), left(-) to right(+)
    fx = [-0.74, -0.87, -0.935, -0.88, -0.76, -0.58, 0.58, 0.76, 0.88, 0.935, 0.87, 0.74]
    fr = [0.03, 0.20, 0.51, 0.80, 0.97, None, None, 0.97, 0.80, 0.51, 0.20, 0.03]
    path = []
    for x_, r_ in zip(fx, fr):
        path.append((x_ * hw, rb if r_ is None else rim_r + r_ * H))
    inner_r = rim_r - 0.03 * H - 0.006
    prof = [(-0.72 * hw, inner_r)] + path + [(0.72 * hw, inner_r)]
    mb.revolve(prof, X0, X1, segs=segs, mat=0, loop=True, up=(0, 0, 1))

    # tread lugs
    step = 2 * pi / max(lugs, 1)

    def lug(cross, th_c, half, taper_top=0.78):
        """cross = [(x, r, is_top)], swept between two angular stations th_c -/+ half (top points narrower)."""
        stat = []
        for s in (-1, 1):
            ring = []
            for (x_, r_, top) in cross:
                a_ = th_c + s * half * (taper_top if top else 1.0)
                ring.append(mb._vert(Vector((x_, r_ * sin(a_), r_ * cos(a_)))))
            stat.append(ring)
        k = len(cross)
        faces = [mb._f([stat[0][i], stat[0][(i + 1) % k], stat[1][(i + 1) % k], stat[1][i]], 0) for i in range(k)]
        faces += mb._cap(stat[0][::-1], 0)
        faces += mb._cap(stat[1], 0)
        mb._close(faces)

    def outward_normals(pts):
        res = []
        for i, (x_, r_) in enumerate(pts):
            a_ = pts[max(i - 1, 0)]
            b_ = pts[min(i + 1, len(pts) - 1)]
            tx, tr = b_[0] - a_[0], b_[1] - a_[1]
            ln = sqrt(tx * tx + tr * tr) or 1.0
            res.append((-tr / ln, tx / ln))      # tangent (tx,tr) rotated +90deg -> outward when walking -x -> +x
        return res

    def shoulder(sign):
        # base polyline along the shoulder: sidewall bulge .. shoulder .. tread edge .. into the tread
        if sign < 0:
            base = [path[2], path[3], path[4], path[5], (-0.40 * hw, rb)]
        else:
            base = [(0.40 * hw, rb), path[6], path[7], path[8], path[9]]
        nrm = outward_normals(base)
        hs = [0.25, 0.40, 0.95, 1.0, 1.0] if sign < 0 else [1.0, 1.0, 0.95, 0.40, 0.25]
        bot = [(b[0] - n[0] * 0.003, b[1] - n[1] * 0.003, False) for b, n in zip(base, nrm)]
        top = [(b[0] + n[0] * lug_h * h, b[1] + n[1] * lug_h * h, True) for b, n, h in zip(base, nrm, hs)]
        return bot + top[::-1]

    left_sh, right_sh = shoulder(-1), shoulder(+1)
    cl = [(-0.42 * hw, rb - 0.003, False), (-0.38 * hw, rb + lug_h, True), (-0.04 * hw, rb + lug_h, True),
          (-0.02 * hw, rb - 0.003, False)]
    cr = [(0.02 * hw, rb - 0.003, False), (0.04 * hw, rb + lug_h, True), (0.38 * hw, rb + lug_h, True),
          (0.42 * hw, rb - 0.003, False)]
    for i in range(lugs):
        th = i * step
        lug(left_sh, th, 0.34 * step)
        lug(right_sh, th + 0.5 * step, 0.34 * step)
        lug(cl, th + 0.5 * step, 0.30 * step)
        lug(cr, th, 0.30 * step)

    # rim barrel (thin closed loop shell)
    rl = rim_r
    prof_rim = [(0.90 * hw, rl + 0.010), (0.70 * hw, rl + 0.004), (-0.90 * hw, rl + 0.010), (-0.90 * hw, rl - 0.008),
                (0.90 * hw, rl - 0.008)]
    mb.revolve(prof_rim, X0, X1, segs=segs, mat=1, loop=True)
    # brake drum + disc
    mb.cyl(Vector((-0.55 * hw, 0, 0)), Vector((0.30 * hw, 0, 0)), 0.58 * rim_r, segs=32 if lod < 2 else 12, mat=1)
    # spokes
    sx = 0.40 * hw
    for k in range(spokes):
        a_ = 2 * pi * k / spokes + pi / spokes
        d = Vector((0, sin(a_), cos(a_)))
        mb.beam(Vector((sx, 0, 0)) + d * (0.22 * rim_r), Vector((sx, 0, 0)) + d * (rim_r - 0.004),
                0.20 * rim_r, 0.16 * hw, up=(1, 0, 0), mat=1, w1=0.26 * rim_r)
    # inner dish ring around the hub
    mb.cyl(Vector((0.30 * hw, 0, 0)), Vector((0.52 * hw, 0, 0)), 0.40 * rim_r, 0.32 * rim_r, segs=24, mat=1)
    # hub + cap + nuts
    mb.cyl(Vector((0.50 * hw, 0, 0)), Vector((0.66 * hw, 0, 0)), 0.30 * rim_r, 0.28 * rim_r, segs=24, mat=2)
    mb.cyl(Vector((0.66 * hw, 0, 0)), Vector((0.74 * hw, 0, 0)), 0.17 * rim_r, 0.12 * rim_r, segs=16, mat=2)
    for k in range(bolts):
        a_ = 2 * pi * k / bolts
        c = Vector((0.66 * hw, 0.235 * rim_r * sin(a_), 0.235 * rim_r * cos(a_)))
        mb.cyl(c, c + Vector((0.09 * hw, 0, 0)), 0.045 * rim_r, segs=6, mat=2, caps=(False, True))
    for k in range(beadlock):
        a_ = 2 * pi * (k + 0.5) / beadlock
        c = Vector((0.90 * hw, (rl + 0.001) * sin(a_), (rl + 0.001) * cos(a_)))
        mb.cyl(c, c + Vector((0.07 * hw, 0, 0)), 0.035 * rim_r, segs=6, mat=2, caps=(False, True))

    if not left:
        rot_z_deg += 180.0
    if abs(rot_z_deg) > 1e-6:
        mb.transform(Matrix.Rotation(radians(rot_z_deg), 4, 'Z'))
    loc = _v(loc)
    mb.translate(loc)
    rz = rot_z_deg % 180.0
    uvm = 'cyl_x' if rz < 1e-6 else ('cyl_y' if abs(rz - 90.0) < 1e-6 else 'box')
    return mb.finish(collection, parent, origin=loc if origin is None else origin, smooth=40.0, uv=uvm)


# ----------------------------------------------------------------------------- LOD
def decimate_lod(obj, ratio, suffix="_LOD1", collection=None, min_tris=40, parent=None, floor_tris=0):
    """Return a decimated (collapse) copy named <obj>_LODn with identical origin/transform/materials/parent.
    Meshes with <= min_tris are copied unchanged; floor_tris keeps small panels from collapsing into holes."""
    base = obj.name
    full = base + suffix
    _claim(full)
    tris = tri_count(obj)
    if tris <= min_tris:
        me = obj.data.copy()
    else:
        mod = obj.modifiers.new("__dec", 'DECIMATE')
        mod.decimate_type = 'COLLAPSE'
        mod.ratio = max(0.02, min(1.0, max(ratio, floor_tris / float(tris))))
        bpy.context.view_layer.update()
        dg = bpy.context.evaluated_depsgraph_get()
        ev = obj.evaluated_get(dg)
        me = bpy.data.meshes.new_from_object(ev, preserve_all_data_layers=True, depsgraph=dg)
        obj.modifiers.remove(mod)
    me.name = full
    new = bpy.data.objects.new(full, me)
    new.matrix_basis = obj.matrix_basis.copy()
    colls = [collection] if collection else list(obj.users_collection)
    for c in colls:
        c.objects.link(new)
    par = parent or obj.parent
    if par is not None:
        new.parent = par
        new.matrix_parent_inverse = obj.matrix_parent_inverse.copy()
    shade_smooth_by_angle(new, 40.0)
    return new


def make_lods(ctx, ratios=(0.45, 0.18), min_tris=40, skip=("COL_",), floors=(70, 40)):
    """Create <Mesh>_LOD1 / _LOD2 copies of every renderable mesh under the asset root into the LOD collections."""
    res = {1: [], 2: []}
    src = [o for o in asset_objects(ctx.root, include_root=False)
           if o.type == 'MESH' and not LOD_RE.search(o.name)
           and not any(clean_name(o.name, ctx.prefix).startswith(s) for s in skip)]
    for o in src:
        for lvl, ratio, coll in ((1, ratios[0], ctx.lod1), (2, ratios[1], ctx.lod2)):
            ld = decimate_lod(o, ratio, "_LOD%d" % lvl, collection=coll, min_tris=min_tris, parent=ctx.root,
                              floor_tris=floors[lvl - 1])
            res[lvl].append(ld)
    return res


def show_lod(ctx, level=0):
    """Inspect LODs: level 0 shows the high LOD, 1/2 shows only that LOD set (high meshes hidden). Call with 0 to restore."""
    for coll, lvl in ((ctx.lod1, 1), (ctx.lod2, 2)):
        lc = find_layer_collection(coll.name)
        if lc:
            lc.exclude = (lvl != level)
    for o in asset_objects(ctx.root, include_root=False):
        if LOD_RE.search(o.name) or clean_name(o.name, ctx.prefix).startswith("COL_"):
            continue
        try:
            o.hide_set(level != 0)
        except RuntimeError:
            pass


def remove_lods(ctx):
    for coll in (ctx.lod1, ctx.lod2):
        purge_collection(coll)


# ----------------------------------------------------------------------------- validation
def _mesh_islands_volume(me):
    """Closed manifold islands of a mesh -> list of (n_faces, signed_volume); an island with inconsistent winding
    is reported with volume -1 (always an error)."""
    bm = bmesh.new()
    bm.from_mesh(me)
    res = []
    for isl, closed, consistent in _islands(bm):
        if closed and len(isl) >= 4:
            res.append((len(isl), _signed_volume(isl) if consistent else -1.0))
    bm.free()
    return res


def validate_asset(asset, expect=None, verbose=True, strict_prefix=True):
    """Print + return a QA dict.  asset = root empty / name.  expect (all optional):
       dims=(L(y),W(x),H(z)) tol=0.05, max_objects=60, max_tris=120000, required=[clean names]"""
    root, _all = resolve_asset(asset)
    pfx = root.name + "__"
    expect = expect or {}
    objs = asset_objects(root, include_root=False)
    meshes = [o for o in objs if o.type == 'MESH']
    empties = [o for o in objs if o.type == 'EMPTY']
    errors, warns = [], []
    cn = lambda o: clean_name(o.name, pfx)

    def is_col(o):
        return cn(o).startswith("COL_")

    def is_lod(o):
        return bool(LOD_RE.search(o.name))
    high = [o for o in meshes if not is_col(o) and not is_lod(o)]
    lods = [o for o in meshes if is_lod(o)]
    cols = [o for o in meshes if is_col(o)]
    mn, mx = bbox_world(high)
    dims = (mx.y - mn.y, mx.x - mn.x, mx.z - mn.z)
    tris = sum(tri_count(o) for o in high)
    tris_lod = {1: 0, 2: 0}
    for o in lods:
        m = LOD_RE.search(o.name)
        tris_lod[int(m.group(1))] = tris_lod.get(int(m.group(1)), 0) + tri_count(o)
    # root
    if root.matrix_world.translation.length > 1e-4 or any(abs(a) > 1e-6 for a in root.rotation_euler) \
            or any(abs(s - 1) > 1e-6 for s in root.scale):
        errors.append("root transform not identity")
    # names
    for o in objs:
        if DEFAULT_NAME_RE.match(cn(o)) or re.search(r"\.\d{3}$", o.name):
            errors.append("default/suffixed name: " + o.name)
        if strict_prefix and not o.name.startswith(pfx):
            errors.append("missing asset prefix: " + o.name)
        if o.parent is None:
            errors.append("unparented: " + o.name)
    # per mesh checks
    flipped, nouv, ngon, badxf, badmat, degen_uv = [], [], [], [], [], []
    for o in meshes:
        me = o.data
        if any(len(p.vertices) > 8 for p in me.polygons):
            ngon.append(o.name)
        if o.scale[:] != (1.0, 1.0, 1.0) and any(abs(s - 1) > 1e-5 for s in o.scale):
            badxf.append(o.name + " scale")
        if any(abs(a) > 1e-5 for a in o.rotation_euler):
            badxf.append(o.name + " rot")
        if o.rotation_mode == 'QUATERNION' and (o.rotation_quaternion - Quaternion()).magnitude > 1e-5:
            badxf.append(o.name + " rotq")
        if is_col(o):
            if len(me.vertices) > 24:
                warns.append("collision proxy has %d verts: %s" % (len(me.vertices), o.name))
            continue
        if not me.uv_layers:
            nouv.append(o.name)
        else:
            uvl = me.uv_layers[0].data
            bad = 0
            for p in me.polygons:
                uvs = [uvl[li].uv for li in p.loop_indices]
                ar = 0.0
                for i in range(1, len(uvs) - 1):
                    a_, b_, c_ = uvs[0], uvs[i], uvs[i + 1]
                    ar += abs((b_[0] - a_[0]) * (c_[1] - a_[1]) - (b_[1] - a_[1]) * (c_[0] - a_[0])) * 0.5
                if ar < 1e-10:
                    bad += 1
            if bad:
                degen_uv.append("%s(%d)" % (o.name, bad))
        for s in o.material_slots:
            if s.material is None or s.material.name not in MR_TABLE:
                badmat.append(o.name)
                break
        if not me.materials:
            badmat.append(o.name + " (no material)")
        for (nf, vol) in _mesh_islands_volume(me):
            if vol < (-2e-5 if is_lod(o) else -1e-7):
                flipped.append("%s(%d faces, vol %.2e)" % (o.name, nf, vol))
    if ngon:
        errors.append("n-gons > 8: %s" % ngon[:6])
    if nouv:
        errors.append("no UVs: %s" % nouv[:8])
    if degen_uv:
        warns.append("degenerate UV faces: %s" % degen_uv[:8])
    if badxf:
        errors.append("unapplied transforms: %s" % badxf[:8])
    if badmat:
        errors.append("bad/missing materials: %s" % sorted(set(badmat))[:8])
    if flipped:
        errors.append("inverted closed islands: %s" % flipped[:8])
    # expectations
    if "dims" in expect:
        tol = expect.get("tol", 0.05)
        for lab, got, want in zip("LWH", dims, expect["dims"]):
            if abs(got - want) > tol:
                errors.append("dimension %s = %.3f, expected %.3f +-%.2f" % (lab, got, want, tol))
    if "max_objects" in expect and len(high) > expect["max_objects"]:
        errors.append("%d high-LOD mesh objects > %d" % (len(high), expect["max_objects"]))
    if "max_tris" in expect and tris > expect["max_tris"]:
        errors.append("%d high-LOD tris > %d" % (tris, expect["max_tris"]))
    names = {cn(o) for o in objs}
    for r in expect.get("required", []):
        if r not in names:
            errors.append("missing required node " + r)
    one = "%s | tris %d (LOD1 %d, LOD2 %d) | mesh objs %d (+%d LOD, %d COL) | empties %d | dims L%.3f W%.3f H%.3f | y[%.3f..%.3f]" % (
        root.name, tris, tris_lod.get(1, 0), tris_lod.get(2, 0), len(high), len(lods), len(cols), len(empties),
        dims[0], dims[1], dims[2], mn.y, mx.y)
    if verbose:
        print("VALIDATE", one)
        for e in errors:
            print("  ERROR:", e)
        for w in warns:
            print("  warn :", w)
        if not errors:
            print("  OK: no errors")
    return dict(ok=not errors, errors=errors, warnings=warns, dims=dims, tris=tris, tris_lod=tris_lod,
                n_mesh=len(high), n_lod=len(lods), n_col=len(cols), n_empty=len(empties), report=one,
                bbox=(tuple(mn), tuple(mx)))


def check_vehicle_contract(asset, axle_ys, hub_z, track, tyre_r, tyre_w, axles=("Front", "Rear"), tol=0.01):
    """ART_SPEC 4.x: wheels at exact hub positions, required nodes/markers present. Returns list of problems."""
    root, _all = resolve_asset(asset)
    pfx = root.name + "__"
    byname = {clean_name(o.name, pfx): o for o in asset_objects(root, include_root=False)}
    problems = []
    names = []
    wl = {"FL": (track / 2, axle_ys[0]), "FR": (-track / 2, axle_ys[0]), "RL": (track / 2, axle_ys[-1]),
          "RR": (-track / 2, axle_ys[-1])}
    for k, (x, y) in wl.items():
        o = byname.get("Wheel_" + k)
        if o is None:
            problems.append("missing Wheel_" + k)
            continue
        p = o.matrix_world.translation
        if abs(p.x - x) > tol or abs(p.y - y) > tol or abs(p.z - hub_z) > tol:
            problems.append("Wheel_%s origin %s expected %s" % (k, tuple(round(c, 3) for c in p), (x, y, hub_z)))
        w = [o.matrix_world @ Vector(c) for c in o.bound_box]
        zmin = min(c.z for c in w)
        dx = max(c.x for c in w) - min(c.x for c in w)
        if abs(zmin) > 0.02:
            problems.append("Wheel_%s lowest point %.3f (should touch ground)" % (k, zmin))
        if abs(dx - tyre_w) > 0.03:
            problems.append("Wheel_%s width %.3f expected %.3f" % (k, dx, tyre_w))
    for ax in axles:
        if "Axle_" + ax not in byname:
            problems.append("missing Axle_" + ax)
        for s in "LR":
            for n in ("Spring_%s_%s" % (ax, s), "Shock_%s_%s_Body" % (ax, s), "Shock_%s_%s_Rod" % (ax, s),
                      "Mount_Spring_%s_%s_Top" % (ax, s), "Mount_Spring_%s_%s_Bot" % (ax, s),
                      "Mount_Shock_%s_%s_Top" % (ax, s), "Mount_Shock_%s_%s_Bot" % (ax, s)):
                if n not in byname:
                    problems.append("missing " + n)
    for n in ("Chassis", "SteeringWheel", "Dash", "Seat_Driver", "Seat_Passenger", "Light_Head_L", "Light_Head_R",
              "Light_Tail_L", "Light_Tail_R", "Anchor_Hitch", "Cam_Cockpit", "Intake", "Exhaust", "CargoOrigin",
              "Fuel_Cap"):
        if n not in byname:
            problems.append("missing " + n)
    if "Anchor_Winch" not in byname and "Anchor_TowFront" not in byname:
        problems.append("missing Anchor_Winch / Anchor_TowFront")
    byname = {k: o for k, o in byname.items() if not LOD_RE.search(k)}      # LOD copies are not contract nodes
    for k, o in byname.items():
        if k.startswith("Link_") and o.type == 'MESH':
            body = byname.get("Mount_" + k + "_Body")
            axle = byname.get("Mount_" + k + "_Axle")
            if body is None or axle is None:
                problems.append("link %s has no Mount_..._Body/_Axle markers" % k)
            elif (o.matrix_world.translation - body.matrix_world.translation).length > 0.02:
                problems.append("link %s origin not on its body marker" % k)
    for k, o in byname.items():
        if k.startswith("Spring_") and o.type == 'MESH':
            top = byname.get("Mount_" + k + "_Top")
            if top and (o.matrix_world.translation - top.matrix_world.translation).length > 0.02:
                problems.append("%s origin not on Top marker" % k)
        if k.startswith("Shock_") and k.endswith("_Body") and o.type == 'MESH':
            top = byname.get("Mount_" + k[:-5] + "_Top")
            if top and (o.matrix_world.translation - top.matrix_world.translation).length > 0.02:
                problems.append("%s origin not on Top marker" % k)
        if k.startswith("Shock_") and k.endswith("_Rod") and o.type == 'MESH':
            bot = byname.get("Mount_" + k[:-4] + "_Bot")
            if bot and (o.matrix_world.translation - bot.matrix_world.translation).length > 0.02:
                problems.append("%s origin not on Bot marker" % k)
    print("VEHICLE CONTRACT:", "OK" if not problems else "%d problem(s)" % len(problems))
    for p in problems:
        print("  -", p)
    return problems


# ----------------------------------------------------------------------------- export
def export_asset(asset, out_path, scratch_dir=None, verbose=True):
    """export_asset("Scout", path) | export_asset(root_obj, path) | export_asset(["Veh_Scout", "COL_Scout"], path).
    Export the asset (root empty + all descendants: meshes, empties, collision proxies, LODs) with the exact
    ART_SPEC recipe to <scratch>/<name>.fbx and move it to out_path. Temporarily strips the '<Asset>__' prefix from
    object + mesh names and un-hides/enables every involved collection/object; everything is restored afterwards."""
    root, objs = resolve_asset(asset)
    if root not in objs:
        objs.insert(0, root)
    pfx = root.name + "__"
    scratch_dir = scratch_dir or SCRATCH_DIR
    os.makedirs(scratch_dir, exist_ok=True)
    tmp = os.path.join(scratch_dir, root.name + ".fbx")
    if os.path.exists(tmp):
        os.remove(tmp)
    try:
        if bpy.context.object and bpy.context.object.mode != 'OBJECT':
            bpy.ops.object.mode_set(mode='OBJECT')
    except Exception:
        pass
    # remember + force visibility of every collection that holds asset objects (and their ancestors)
    pmap = _collection_parent_map()
    need = set()
    for o in objs:
        for c in o.users_collection:
            need.add(c.name)
            p = pmap.get(c.name)
            while p:
                need.add(p)
                p = pmap.get(p)
    saved_lc = [(lc, lc.exclude, lc.hide_viewport, lc.collection.hide_viewport) for lc in _iter_layer_collections()]
    for lc, ex, hv, chv in saved_lc:
        if lc.name in need:
            lc.exclude = False
            lc.hide_viewport = False
            lc.collection.hide_viewport = False
    saved_obj = [(o, o.hide_viewport, o.hide_get(), o.hide_select) for o in objs]
    renames = []
    try:
        for o in objs:
            o.hide_viewport = False
            o.hide_select = False
            try:
                o.hide_set(False)
            except RuntimeError:
                pass
        # strip prefix (objects + mesh data)
        for o in objs:
            if o is root:
                continue
            if o.name.startswith(pfx):
                clean = o.name[len(pfx):]
                clash = bpy.data.objects.get(clean)
                if clash is not None and clash not in objs:
                    raise RuntimeError("export name clash with foreign object %r" % clean)
                renames.append((o, o.name, o.data.name if o.data else None))
        for o, oname, dname in renames:
            o.name = oname[len(pfx):]
            if o.data is not None and o.data.users == 1 and dname and dname.startswith(pfx):
                o.data.name = dname[len(pfx):]
        for o, oname, dname in renames:
            if o.name != oname[len(pfx):]:
                raise RuntimeError("rename failed %r -> %r" % (oname, o.name))
        bpy.ops.object.select_all(action='DESELECT')
        for o in objs:
            o.select_set(True)
        bpy.context.view_layer.objects.active = root
        bpy.ops.export_scene.fbx(filepath=tmp, use_selection=True, object_types={'MESH', 'EMPTY'},
                                 apply_scale_options='FBX_SCALE_ALL', global_scale=1.0, axis_forward='-Z',
                                 axis_up='Y', bake_space_transform=True, use_mesh_modifiers=True,
                                 mesh_smooth_type='FACE', add_leaf_bones=False, bake_anim=False,
                                 path_mode='STRIP', use_custom_props=False)
    finally:
        for o, oname, dname in reversed(renames):
            o.name = oname
            if o.data is not None and dname:
                o.data.name = dname
        for o, hv, hs, hsel in saved_obj:
            o.hide_viewport = hv
            o.hide_select = hsel
            try:
                o.hide_set(hs)
            except RuntimeError:
                pass
        for lc, ex, hv, chv in saved_lc:
            lc.exclude = ex
            lc.hide_viewport = hv
            lc.collection.hide_viewport = chv
        bpy.ops.object.select_all(action='DESELECT')
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    if os.path.exists(out_path):
        os.remove(out_path)
    shutil.move(tmp, out_path)
    size = os.path.getsize(out_path)
    if verbose:
        print("EXPORTED %s (%d bytes, %d objects)" % (out_path, size, len(objs)))
    return dict(path=out_path, bytes=size, objects=len(objs))


def default_export_path(name, category="Vehicles"):
    return os.path.join(ART_ROOT, CATEGORY_COLLECTIONS[category][2], name, name + ".fbx")


# ----------------------------------------------------------------------------- props extensions (collision hulls, cut-disc UVs)
def create_collision_hull(name, centre, local_verts, local_faces, parent=None, collection=None, prefix=True):
    """Collision proxy from explicit verts/faces (convex hull, <= 24 verts per ART_SPEC 5). Verts are relative to `centre`;
    faces are index tuples with outward winding. No material, no UVs; displayed as wire, not rendered."""
    full = nm(name) if prefix else name
    _claim(full)
    me = bpy.data.meshes.new(full)
    me.from_pydata([tuple(v) for v in local_verts], [], [tuple(f) for f in local_faces])
    me.update()
    o = bpy.data.objects.new(full, me)
    o.location = _v(centre)
    (collection or (ACTIVE.col_coll if ACTIVE else bpy.context.scene.collection)).objects.link(o)
    if parent is not None:
        parent_to(o, parent)
    o.display_type = 'WIRE'
    o.hide_render = True
    return o


def create_collision_prism(name, centre, axis, length, radius, sides=8, radius2=None, parent=None, collection=None, prefix=True,
                           tangent=True):
    """Convex n-sided prism / frustum along a world axis ('X'|'Y'|'Z'), centred on `centre` (capsule-ish proxy for logs,
    barrels, stumps).  tangent=True: `radius` is the APOTHEM (flat faces touch the real cylinder; one flat face points
    down/-Z for 'X'/'Y' axes).  2*sides verts, sides+2 faces."""
    r2 = radius if radius2 is None else radius2
    k = 1.0 / cos(pi / sides) if tangent else 1.0
    phase = pi / sides
    verts, faces = [], []
    for end, rr in ((-0.5, radius), (0.5, r2)):
        for i in range(sides):
            a = phase + 2 * pi * i / sides
            c, s_ = cos(a) * rr * k, sin(a) * rr * k
            if axis == 'Y':
                verts.append((c, end * length, s_))
            elif axis == 'X':
                verts.append((end * length, c, s_))
            else:
                verts.append((c, s_, end * length))
    n = sides
    for i in range(n):
        j = (i + 1) % n
        faces.append((i, j, n + j, n + i))
    if n <= 8:
        faces.append(tuple(range(n - 1, -1, -1)))
        faces.append(tuple(range(n, 2 * n)))
    else:                                        # caps as triangle fans (no n-gon > 8)
        for i in range(1, n - 1):
            faces.append((0, i + 1, i))
            faces.append((n, n + i, n + i + 1))
    o = create_collision_hull(name, centre, verts, faces, parent, collection, prefix)
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bm.normal_update()
    if _signed_volume(list(bm.faces)) < 0:
        bmesh.ops.reverse_faces(bm, faces=list(bm.faces))
    bm.to_mesh(o.data)
    bm.free()
    return o


def uv_discs(obj, mat_index):
    """Re-map every connected island of faces carrying material slot `mat_index` (cut log ends, stump tops, stub tips) to
    a centred disc: planar projection on the island's best-fit plane, 0..1 across the island's diameter, centre (0.5, 0.5)."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.normal_update()
    uv = _uv_layer(bm)
    seen = set()
    faces = [f for f in bm.faces if f.material_index == mat_index]
    fset = set(f.index for f in faces)
    for f in faces:
        if f.index in seen:
            continue
        stack, isl = [f], []
        seen.add(f.index)
        while stack:
            cur = stack.pop()
            isl.append(cur)
            for e in cur.edges:
                for nf in e.link_faces:
                    if nf.index in fset and nf.index not in seen:
                        seen.add(nf.index)
                        stack.append(nf)
        verts = {v for ff in isl for v in ff.verts}
        c = sum((v.co for v in verts), Vector()) / len(verts)
        n = sum((ff.normal * ff.calc_area() for ff in isl), Vector())
        if n.length < 1e-9:
            n = Vector((0, 0, 1))
        n.normalize()
        u_ax, w_ax, _a = axis_basis(n)
        rad = max((v.co - c).length for v in verts) or 1.0
        for ff in isl:
            for l in ff.loops:
                d = l.vert.co - c
                l[uv].uv = (0.5 + d.dot(u_ax) / (2 * rad), 0.5 + d.dot(w_ax) / (2 * rad))
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()


# ----------------------------------------------------------------------------- self test
def primitive_check(verbose=True):
    """Every MeshBuilder primitive must be born with consistent, outward winding (no reliance on the fixer)."""
    V_ = Vector
    cases = {
        "box": lambda m: m.box((0.3, 0.2, 0.1), (1, 2, 3)),
        "box_rot": lambda m: m.box((0.3, 0.2, 0.1), (1, 2, 3), rot=(0.3, 0.5, 0.7)),
        "rbox": lambda m: m.rbox((0.3, 0.2, 0.1), (1, 2, 0.5), r=0.1, steps=2),
        "rbox_rot": lambda m: m.rbox((0.3, 0.2, 0.1), (0.4, 1.2, 0.3), r=0.05, steps=1, rot=(0.3, 0.5, 0.7)),
        "rbox_cube": lambda m: m.rbox((0.3, 0.2, 0.1), (0.4, 0.4, 0.4), r=0.2, steps=3),
        "beam": lambda m: m.beam((0.2, 0.2, 0.2), (1.2, 0.5, 0.9), 0.1, 0.05, w1=0.2),
        "cyl_x": lambda m: m.cyl((0.4, 0.1, 0.2), (1.4, 0.1, 0.2), 0.1, segs=10),
        "cyl_y": lambda m: m.cyl((0.4, 0.1, 0.2), (0.4, 1.1, 0.2), 0.1, 0.05, segs=10),
        "cyl_z": lambda m: m.cyl((0.4, 0.1, 0.2), (0.4, 0.1, 1.2), 0.1, segs=10),
        "cone": lambda m: m.cone((0.4, 0.1, 0.2), (0.4, 0.6, 1.2), 0.2, segs=10),
        "cyl_nocap": lambda m: m.cyl((0.4, 0.1, 0.2), (0.4, 0.1, 1.2), 0.1, segs=10, caps=(False, True)),
        "revolve": lambda m: m.revolve([(0, 0), (0.1, 0.1), (0.3, 0.08), (0.4, 0)], (0.5, 0.3, 0.2), (0.5, 0.3, 1.2), segs=12),
        "revolve_capped": lambda m: m.revolve([(0, 0.1), (0.1, 0.12), (0.4, 0.09)], (0.5, 0.3, 0.2), (0.5, 1.3, 0.2), segs=12),
        "revolve_loop": lambda m: m.revolve([(0, 0.2), (0.1, 0.2), (0.1, 0.15), (0, 0.15)], (0.5, 0.3, 0.2), (1.5, 0.3, 0.2), segs=16, loop=True),
        "sphere": lambda m: m.sphere((0.2, 0.3, 0.4), 0.2),
        "prism_yz": lambda m: m.prism([(0, 0), (1, 0), (1, 0.5), (0.5, 0.2), (0, 0.5)], 'YZ', 0.1, 0.3),
        "prism_xz": lambda m: m.prism([(0, 0), (1, 0), (1, 0.5), (0.5, 0.2), (0, 0.5)], 'XZ', 0.1, 0.3),
        "prism_xy_cw": lambda m: m.prism([(0, 0), (0, 0.5), (1, 0.5), (1, 0)], 'XY', 0.1, 0.3),
        "coil": lambda m: m.coil((0.3, 0.3, 1.2), (0.3, 0.3, 0.7), 0.06, 0.008, turns=7),
        "tube": lambda m: m.tube_path([(0, 0, 0), (0, 0, 0.5), (0.4, 0, 0.8), (0.4, 0.5, 0.8)], 0.02, fillet=0.1),
        "torus": lambda m: m.torus((0.1, 0.2, 0.3), (0, 0.8, 0.5), 0.17, 0.014),
        "hexa": lambda m: m.hexa([(0, 0, 0), (1, 0, 0), (1, 1, 0), (0, 1, 0), (0, 0, 1), (1, 0, 1), (1, 1, 1), (0, 1, 1.5)]),
    }
    bad = []
    for name, fn in cases.items():
        m = MeshBuilder("pc", ["MR_MetalDark"])
        fn(m)
        for isl, closed, consistent in _islands(m.bm):
            if not closed or len(isl) < 4:
                continue
            vol = _signed_volume(isl)
            if not consistent or vol <= 0:
                bad.append("%s (consistent=%s vol=%.5f)" % (name, consistent, vol))
                break
        m.bm.free()
    if verbose:
        print("PRIMITIVE CHECK", "OK (%d primitives)" % len(cases) if not bad else "FAIL: %s" % bad)
    return not bad


def selftest(keep=False):
    """Builds a tiny throw-away asset 'ZTest' with every primitive, validates, exports to the scratch folder
    only, then deletes everything it created. Prints PASS/FAIL."""
    global ACTIVE
    saved_active = ACTIVE
    A = begin_asset("ZTest", clean=True, isolate=False)
    try:
        mb = MeshBuilder("Body", ["MR_Paint", "MR_MetalDark"])
        mb.box((0, 0, 0.5), (1, 2, 0.2))
        mb.cyl((0, 0, 0.6), (0, 0, 1.0), 0.2, 0.1, segs=16, mat=1)
        mb.beam((0.2, 0.2, 0.2), (0.6, 0.5, 0.4), 0.05, 0.05, mat=1)
        mb.prism([(0, 0), (1, 0), (1, 0.5), (0.5, 0.2), (0, 0.5)], 'YZ', 0.0, 0.1, mat=0)
        m = mb.mark()
        mb.revolve([(0, 0), (0.1, 0.1), (0.2, 0.08), (0.3, 0)], (0.5, 0, 0.5), (0.5, 0, 1.0), segs=12, mat=1)
        mb.coil((0.3, 0.3, 1.2), (0.3, 0.3, 0.7), 0.06, 0.008, turns=7, mat=1)
        mb.tube_path([(0, 0, 0), (0, 0, 0.5), (0.4, 0, 0.8), (0.4, 0.5, 0.8)], 0.02, fillet=0.1, mat=1)
        mb.mirror_x(since=m)
        body = mb.finish(A.coll, A.root, origin=(0, 0, 0))
        w = make_wheel("Wheel_FL", R=0.40, W=0.235, loc=(0.75, -1.25, 0.40), left=True, parent=A.root, collection=A.coll)
        w2 = make_wheel("Wheel_FR", R=0.40, W=0.235, loc=(-0.75, -1.25, 0.40), left=False, parent=A.root, collection=A.coll)
        # join / origin / transforms / smart-UV helpers
        parts = []
        for k in range(3):
            m2 = MeshBuilder("TmpPart%d" % k, ["MR_Rubber" if k else "MR_Paint"])
            m2.box((k * 0.5, 3.0, 0.2), (0.3, 0.3, 0.3))
            parts.append(m2.finish(A.coll, A.root, origin=(k * 0.5, 3.0, 0.2)))
        parts[1].rotation_euler = (0.0, 0.0, 0.5)
        parts[2].scale = (1.0, 2.0, 1.0)
        apply_transforms(parts)
        set_origin(parts[0], (0.0, 3.0, 0.0))
        jb = join_by_material(parts, "{asset}_Joined_{mat}", A.coll, A.root)
        ok_join = len(jb) == 2 and all(len(o.data.polygons) > 0 for o in jb)
        unwrap(jb[0], 'smart')
        ok_join = ok_join and len(jb[0].data.uv_layers) >= 1
        for o in jb:
            nm_ = clean_name(o.name)
            o.name = nm("Joined_" + nm_.split("_")[-1])
        create_empty("Mount_Test", (0, 0, 1), parent=A.root, collection=A.coll)
        create_collision_box("COL_Test", (0, 0, 0.5), (1, 2, 0.4), parent=A.root)
        lods = make_lods(A, skip=("COL_", "Wheel_"))
        for lvl, coll in ((1, A.lod1), (2, A.lod2)):
            for nme, loc_, left_ in (("Wheel_FL", (0.75, -1.25, 0.40), True), ("Wheel_FR", (-0.75, -1.25, 0.40), False)):
                make_wheel(nme + "_LOD%d" % lvl, R=0.40, W=0.235, loc=loc_, left=left_, parent=A.root, collection=coll, lod=lvl)
                lods[lvl].append(bpy.data.objects[nm(nme + "_LOD%d" % lvl)])
        res = validate_asset(A.root, expect=dict(max_objects=20))
        out = export_asset(A.root, os.path.join(SCRATCH_DIR, "_selftest_out.fbx"))
        ok = primitive_check() and ok_join and res["ok"] and out["bytes"] > 1000 and len(lods[1]) == 5
        # names restored?
        ok = ok and bpy.data.objects.get("ZTest__Wheel_FL") is not None and bpy.data.objects.get("Wheel_FL") is None
        print("SELFTEST", "PASS" if ok else "FAIL", "tris(body)=%d wheel=%d" % (tri_count(body), tri_count(w)))
        return ok
    finally:
        if not keep:
            purge_collection(A.coll)
            purge_collection(A.col_coll)
            r = bpy.data.objects.get("ZTest")
            if r:
                bpy.data.objects.remove(r, do_unlink=True)
            for c in [A.lod1, A.lod2, A.coll, A.col_coll]:
                if c.name in bpy.data.collections:
                    bpy.data.collections.remove(c)
            p = os.path.join(SCRATCH_DIR, "_selftest_out.fbx")
            if os.path.exists(p):
                os.remove(p)
        ACTIVE = saved_active


print("blender_helpers loaded: %d MR materials in table, project root %s" % (len(MR_TABLE), PROJECT_ROOT))
