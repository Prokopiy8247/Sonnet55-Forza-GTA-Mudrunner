"""Material INSTANCES: one MI_<name> for every Blender material slot name of the non-car kits (Exports/**/*.json 'material_slots') plus
the generic variants other agents need.   /Game/Forza/Materials/Instances/MI_<slot name without the leading 'M_'>

The slot -> asset table is also written to Tools/ue/materials_slot_map.json ({"M_Tree_Bark": "/Game/Forza/Materials/Instances/MI_Tree_Bark", ...}) so an
importer can assign materials by NAME.  Parameter names: Docs/Tech/MATERIALS.md.

Layout of this module: `REG` collects dicts; `add()` registers one instance; `build_all()` creates/refreshes everything (idempotent) and writes the map.
Instances of the surface masters (roads, buildings, roadside kit) live in materials_instances_surface.py (same registry via `add`).
"""
import json
import os
import sys

import unreal

_HERE = os.path.dirname(os.path.abspath(globals().get("__file__", unreal.Paths.project_dir() + "Tools/ue/materials_instances.py")))
if _HERE not in sys.path:
    sys.path.insert(0, _HERE)
import materials_lib as L  # noqa: E402
from materials_lib import MAT_ROOT, exists, load, log, new_instance, warn  # noqa: E402
import materials_textures as T  # noqa: E402
unreal = unreal  # re-exported for the registry modules

INST_DIR = MAT_ROOT + "/Instances"
SLOT_MAP_PATH = _HERE + "/materials_slot_map.json"
REG = []
OBSOLETE = ["MI_Grass_Green"]  # was the atlas card grass, now MI_GrassCards_Green (MI_Grass_Dry became the ground-cover slot instance)


def srgb(h, a=1.0):
    """'#rrggbb' (sRGB) -> linear (r, g, b, a) tuple."""
    h = h.lstrip("#")
    r, g, b = [int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]

    def f(c):
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    return (f(r), f(g), f(b), a)


def pbr(setname, names=("BaseColorTex", "NormalTex", "ORMTex")):
    return {names[0]: T.tex_path(setname, "BC"), names[1]: T.tex_path(setname, "N"), names[2]: T.tex_path(setname, "ORM")}


def atlas(setname):
    return pbr(setname, ("AtlasBC", "AtlasN", "AtlasORM"))


def add(name, parent, slot=None, scalars=None, vectors=None, textures=None, switches=None, base_overrides=None, note="", folder=None, phys=None):
    """Register MI `name` (e.g. 'MI_Tree_Bark') of master `parent` ('M_Roam_Bark'); `slot` = Blender slot name it serves.
    folder = optional content folder (default /Game/Forza/Materials/Instances; road kit: /Game/Forza/Materials/Roads, added by M-B)."""
    REG.append({"name": name, "parent": parent, "slot": slot, "scalars": scalars or {}, "vectors": vectors or {}, "textures": textures or {},
                "switches": switches or {}, "base_overrides": base_overrides, "note": note, "folder": folder, "phys": phys})


# ------------------------------------------------------------------------------------------------------------------------------
# nature kit (Docs/Kits/nature_trees.md)
# ------------------------------------------------------------------------------------------------------------------------------
def register_nature():
    # bark: UV unit = 2 m of bark (kit UV_TILE), textures tile 1.2 m (oak/pine) / 1.0 m (birch)
    add("MI_Tree_Bark", "M_Roam_Bark", "M_Tree_Bark", {"UVScaleU": 1.667, "UVScaleV": 1.667, "SpecularBase": 0.25},
        textures=pbr("tree_bark_a"), note="oak / pine / palm / olive / poplar trunks")
    add("MI_Tree_Bark_Birch", "M_Roam_Bark", "M_Tree_Bark_Birch", {"UVScaleU": 2.0, "UVScaleV": 2.0, "NormalStrength": 0.8, "RoughnessScale": 1.0,
                                                                    "VariationAmount": 0.35, "SwayAmplitude": 40.0},
        {"Tint": (0.95, 0.95, 0.93, 1)}, textures=pbr("birch_bark"), note="white paper bark")
    add("MI_Tree_Bark_Dark", "M_Roam_Bark", "M_Tree_Bark_Dark", {"UVScaleU": 1.667, "UVScaleV": 1.667},
        {"Tint": (0.3, 0.3, 0.3, 1)}, textures=pbr("tree_bark_b"), note="birch trunk foot / lenticels")
    add("MI_Tree_Dead", "M_Roam_Bark", "M_Tree_Dead", {"UVScaleU": 1.667, "UVScaleV": 1.667, "Saturation": 0.35, "RoughnessScale": 1.0,
                                                       "SnowResponse": 0.9, "VariationAmount": 0.7, "SwayAmplitude": 10.0},
        {"Tint": (3.4, 3.4, 3.3, 1)}, textures=pbr("tree_bark_a"), note="bleached dead wood (bark texture, light grey-tan)")

    leaf = dict(atlas("leaf_atlas_broadleaf"))
    add("MI_Tree_Leaf", "M_Roam_Foliage_Masked", "M_Tree_Leaf",
        {"AtlasFirstCell": 12, "StripCellCount": 4, "StripMode": 1, "SpecularBase": 0.12, "TranslucencyAmount": 0.35},
        {"Tint": (0.42, 0.62, 0.42, 1)}, textures=leaf, note="oak / poplar broadleaf (twig cards)")
    add("MI_Tree_LeafLight", "M_Roam_Foliage_Masked", "M_Tree_LeafLight",
        {"AtlasFirstCell": 12, "StripCellCount": 4, "StripMode": 1, "SpecularBase": 0.12, "TranslucencyAmount": 0.45},
        {"Tint": (0.95, 0.9, 0.55, 1), "TranslucencyColor": (0.8, 0.9, 0.2, 1)}, textures=leaf, note="birch / poplar light foliage")
    add("MI_Tree_LeafDry", "M_Roam_Foliage_Masked", "M_Tree_LeafDry",
        {"AtlasFirstCell": 12, "StripCellCount": 4, "StripMode": 1, "SpecularBase": 0.12, "TranslucencyAmount": 0.25, "SeasonAmount": 0.0},
        {"Tint": (1.1, 0.8, 1.1, 1), "TranslucencyColor": (0.7, 0.65, 0.3, 1)}, textures=leaf, note="olive / scrub grey-olive foliage")
    add("MI_Tree_Needle", "M_Roam_Foliage_Masked", "M_Tree_Needle",
        {"AtlasFirstCell": 0, "StripCellCount": 4, "StripMode": 1, "SpecularBase": 0.15, "TranslucencyAmount": 0.2, "SnowResponse": 0.7},
        {"Tint": (0.42, 0.58, 0.55, 1), "TranslucencyColor": (0.3, 0.55, 0.2, 1)}, textures=atlas("needle_atlas"), note="spruce / pine / cypress")
    add("MI_Tree_Palm", "M_Roam_Foliage_Masked", "M_Tree_Palm",
        {"AtlasFirstCell": 0, "StripCellCount": 2, "StripMode": 1, "SpecularBase": 0.2, "TranslucencyAmount": 0.4, "SwayAmplitude": 70.0,
         "FlutterAmplitude": 10.0},
        {"Tint": (0.7, 0.8, 0.65, 1)}, textures=atlas("palm_frond_atlas"), note="coconut / date frond cells")
    # far cards: one MI per tree id, slot M_Tree_Far_<id>
    far_dir = T.ROOT + "Exports/Nature/Trees/Textures"
    if os.path.isdir(far_dir):
        for fn in sorted(os.listdir(far_dir)):
            if fn.startswith("T_tree_") and fn.endswith("_Far.png"):
                tid = fn[2:-8]  # tree_oak_a
                add("MI_Tree_Far_" + tid, "M_Roam_Tree_Far", "M_Tree_Far_" + tid, textures={"CardTex": "%s/Nature/T_%s_Far" % (T.TEX_ROOT, tid)},
                    note="distance card of " + tid)
    # rocks (triplanar)
    rk = pbr("rock_grey")
    add("MI_Rock", "M_Roam_Rock", "M_Rock", {"TileMetres": 4.0, "MossEnabled": 0.0}, textures=rk, note="generic grey granite rock")
    add("MI_Rock_Mossy", "M_Roam_Rock", None, {"TileMetres": 4.0, "MossEnabled": 1.0, "MossAmount": 0.8}, textures=rk, note="rock with slope moss")
    add("MI_Rock_Cliff", "M_Roam_Rock", None, {"TileMetres": 8.0, "MossEnabled": 0.0, "BlendSharpness": 6.0}, textures=pbr("rock_cliff"),
        note="layered sedimentary cliff (strata horizontal)")
    add("MI_Rock_RedClay", "M_Roam_Rock", None, {"TileMetres": 4.0, "MossEnabled": 0.0}, textures=pbr("red_clay"), note="canyon / mesa red clay-rock")
    # grass + flowers (cards)
    gr = atlas("grass_blade_atlas")
    add("MI_GrassCards_Green", "M_Roam_Grass_Blade", None, {"AtlasFirstCell": 0, "CellCount": 4, "RandomCells": 1}, textures=gr, note="green tufts (4 variants)")
    add("MI_GrassCards_Dry", "M_Roam_Grass_Blade", None, {"AtlasFirstCell": 4, "CellCount": 4, "RandomCells": 1}, textures=gr, note="dry / straw tufts")
    fl = atlas("flower_atlas")
    add("MI_Flower_Mixed", "M_Roam_Flower", None, {"AtlasFirstCell": 0, "CellCount": 4, "RandomCells": 1}, textures=fl, note="random of 4 flower cards")
    for i, nm in enumerate(("Daisy", "Poppy", "Lavender", "Buttercup")):
        add("MI_Flower_" + nm, "M_Roam_Flower", None, {"AtlasCell": i, "RandomCells": 0}, textures=fl)


def _road_phys(name):
    """Physical surface (PM_Roam_<x>) of an instance in /Game/Forza/Materials/Roads, by name (same table as Tools/ue/import_roads.py FALLBACK)."""
    n = name.lower()
    if "asphalt" in n or "marking" in n:
        return "Asphalt"
    if "dirt" in n:
        return "Dirt"
    if "gravel" in n:
        return "Gravel"
    return "Concrete"   # concrete road, cobble, curb, bridge, tunnel


# ------------------------------------------------------------------------------------------------------------------------------
# ground-cover kit (Docs/Kits/ground_cover.md): bushes, rocks, cacti, grass / flowers / reeds, crops, hay, wood, beach props.
# Blender colours (Tools/blender/nature/gc_lib.py, linear) are matched: modelled foliage / plain parts -> M_Roam_Foliage_Solid (colour parameters),
# rocks / sand / soil / hay -> M_Roam_Rock (triplanar, texture tinted to the Blender colour), wood -> M_Roam_Bark (box-projected UV, 2 m per unit).
# ------------------------------------------------------------------------------------------------------------------------------
_MAN = {}


def _mean_lin(setname):
    if not _MAN:
        with open(T.SRC + "/manifest.json", "r", encoding="utf-8") as fh:
            for st in json.load(fh)["sets"]:
                _MAN[st["name"]] = st
    rgb = _MAN[setname]["albedo_mean_srgb_rgb"]
    return tuple(srgb("#%02x%02x%02x" % tuple(rgb))[:3])


def tint_for(setname, target, lo=0.25, hi=4.0):
    """Colour multiplier that brings the mean albedo of a texture set to the (linear) target colour."""
    m = _mean_lin(setname)
    return tuple(max(lo, min(hi, t / max(mc, 1e-3))) for t, mc in zip(target, m)) + (1.0,)


def register_cover():
    solid = [  # slot, linear colour, roughness, extra scalars
        ("M_Bush_Leaf", (0.09, 0.28, 0.05), 0.55, {"SwayAmplitude": 35.0}),
        ("M_Bush_Leaf_Evergreen", (0.03, 0.13, 0.06), 0.45, {"SwayAmplitude": 28.0}),
        ("M_Bush_Dry", (0.42, 0.30, 0.13), 0.85, {"TranslucencyAmount": 0.15, "SwayAmplitude": 35.0}),
        ("M_Bush_Berry", (0.40, 0.02, 0.03), 0.35, {"WindEnabled": 0.0, "TranslucencyAmount": 0.0, "VariationAmount": 0.3}),
        ("M_Cactus", (0.08, 0.26, 0.11), 0.6, {"WindEnabled": 0.0, "TranslucencyAmount": 0.0, "VariationAmount": 0.4, "SnowResponse": 0.5}),
        ("M_Cactus_Spine", (0.70, 0.60, 0.40), 0.7, {"WindEnabled": 0.0, "TranslucencyAmount": 0.0, "VariationAmount": 0.3}),
        ("M_Cactus_Fruit", (0.50, 0.04, 0.10), 0.4, {"WindEnabled": 0.0, "TranslucencyAmount": 0.0, "VariationAmount": 0.3}),
        ("M_Grass_Blade", (0.10, 0.30, 0.05), 0.6, {"SwayAmplitude": 22.0, "FlutterAmplitude": 3.0, "SnowResponse": 0.2}),
        ("M_Grass_Dry", (0.50, 0.40, 0.17), 0.75, {"SwayAmplitude": 22.0, "FlutterAmplitude": 3.0, "SnowResponse": 0.2, "TranslucencyAmount": 0.2}),
        ("M_Reed", (0.17, 0.30, 0.08), 0.55, {"SwayAmplitude": 30.0, "FlutterAmplitude": 3.0}),
        ("M_Reed_Head", (0.22, 0.10, 0.05), 0.8, {"SwayAmplitude": 30.0, "FlutterAmplitude": 2.0, "TranslucencyAmount": 0.1}),
        ("M_Flower", (0.85, 0.83, 0.80), 0.5, {"SwayAmplitude": 14.0, "FlutterAmplitude": 2.0, "TranslucencyAmount": 0.35}),
        ("M_Flower_B", (0.40, 0.08, 0.50), 0.5, {"SwayAmplitude": 14.0, "FlutterAmplitude": 2.0, "TranslucencyAmount": 0.35}),
        ("M_Flower_Center", (0.85, 0.58, 0.04), 0.6, {"SwayAmplitude": 14.0, "FlutterAmplitude": 2.0, "TranslucencyAmount": 0.1}),
        ("M_Crop", (0.30, 0.34, 0.10), 0.6, {"SwayAmplitude": 25.0}),
        ("M_Crop_Ear", (0.58, 0.42, 0.14), 0.6, {"SwayAmplitude": 25.0, "TranslucencyAmount": 0.2}),
        ("M_Hay_Twine", (0.30, 0.22, 0.09), 0.9, {"WindEnabled": 0.0, "TranslucencyAmount": 0.0, "VariationAmount": 0.3}),
        ("M_Beach_Red", (0.55, 0.04, 0.03), 0.55, {"WindEnabled": 0.0, "TranslucencyAmount": 0.0, "VariationAmount": 0.2}),
        ("M_Beach_White", (0.78, 0.76, 0.70), 0.55, {"WindEnabled": 0.0, "TranslucencyAmount": 0.0, "VariationAmount": 0.2}),
        ("M_Beach_Blue", (0.04, 0.18, 0.50), 0.55, {"WindEnabled": 0.0, "TranslucencyAmount": 0.0, "VariationAmount": 0.2}),
        ("M_Beach_Metal", (0.55, 0.55, 0.57), 0.35, {"WindEnabled": 0.0, "TranslucencyAmount": 0.0, "VariationAmount": 0.1, "Metallic": 0.9, "SpecularBase": 0.5}),
        ("M_Sign_Paint", (0.72, 0.69, 0.58), 0.6, {"WindEnabled": 0.0, "TranslucencyAmount": 0.0, "VariationAmount": 0.2}),
    ]
    for slot, col, rough, extra in solid:
        sc = {"Roughness": rough}
        sc.update(extra)
        add("MI_" + slot[2:], "M_Roam_Foliage_Solid", slot, sc, {"BaseColor": col + (1.0,)}, note="ground-cover kit: " + slot)
    rocks = [  # slot, texture set, linear target colour, tile metres, extra
        ("M_Rock_Slate", "rock_grey", (0.16, 0.17, 0.19), 4.0),
        ("M_Rock_Sandstone", "rock_cliff", (0.40, 0.20, 0.10), 8.0),
        ("M_Rock_SandstoneDark", "rock_cliff", (0.22, 0.09, 0.05), 8.0),
        ("M_Rock_Beach", "rock_grey", (0.33, 0.30, 0.26), 4.0),
        ("M_Sand", "beach_sand", (0.58, 0.47, 0.30), 3.0),
        ("M_Crop_Soil", "farmland_soil", (0.13, 0.08, 0.05), 6.0),
        ("M_Hay", "grass_dry", (0.60, 0.47, 0.20), 1.5),
    ]
    for slot, ts, target, tile in rocks:
        add("MI_" + slot[2:], "M_Roam_Rock", slot, {"TileMetres": tile, "MossEnabled": 0.0, "MacroVariation": 0.4}, {"Tint": tint_for(ts, target)},
            textures=pbr(ts), note="ground-cover kit: %s (triplanar %s)" % (slot, ts))
    woods = [  # slot, texture set, linear target colour, uv scale (kit: box projection, 2 m per UV unit)
        ("M_Wood_Log", "tree_bark_a", (0.16, 0.10, 0.06), 1.667),
        ("M_Wood_LogEnd", "wood_planks_weathered", (0.50, 0.34, 0.19), 1.0),
        ("M_Wood_Plank", "wood_planks_weathered", (0.36, 0.25, 0.15), 1.0),
    ]
    for slot, ts, target, uvs in woods:
        add("MI_" + slot[2:], "M_Roam_Bark", slot, {"UVScaleU": uvs, "UVScaleV": uvs, "SwayAmplitude": 0.0, "FlutterAmplitude": 0.0, "WindEnabled": 0.0,
                                                     "SnowResponse": 0.7},
            {"Tint": tint_for(ts, target)}, textures=pbr(ts), note="ground-cover kit: " + slot)


# ------------------------------------------------------------------------------------------------------------------------------
def build_all():
    REG[:] = []
    register_nature()
    register_cover()
    for modname in ("materials_instances_fx", "materials_instances_surface"):
        if os.path.exists("%s/%s.py" % (_HERE, modname)):
            import importlib
            mod = importlib.reload(sys.modules[modname]) if modname in sys.modules else importlib.import_module(modname)
            mod.register(sys.modules[__name__])
    L.ensure_dir(INST_DIR)
    L.ensure_dir(MAT_ROOT + "/Roads")
    ok, bad = 0, []
    slot_map = {}
    parents = {}
    seen = set()
    for r in REG:
        full = "%s/%s" % (r["folder"], r["name"])
        if full in seen:
            warn("duplicate instance %s skipped (first registration wins)" % full)
            continue
        seen.add(full)
        try:
            if r["parent"] not in parents:
                pp = MAT_ROOT + "/" + r["parent"]
                parents[r["parent"]] = load(pp) if exists(pp) else None
            parent = parents[r["parent"]]
            if parent is None:
                bad.append("%s (parent %s missing)" % (r["name"], r["parent"]))
                continue
            fdir = r.get("folder") or INST_DIR
            L.ensure_dir(fdir)
            mi = new_instance(fdir + "/" + r["name"], parent, r["scalars"], r["vectors"], r["textures"], r["switches"], r["base_overrides"])
            pm_name = r.get("phys") or (_road_phys(r["name"]) if fdir.endswith("/Roads") else None)   # wheel traces read the physical material
            if pm_name:
                pm_path = "%s/Physical/PM_Roam_%s" % (MAT_ROOT, pm_name)
                if exists(pm_path):
                    try:
                        mi.set_editor_property("phys_material", load(pm_path))
                    except Exception as ex:  # noqa: BLE001
                        warn("%s: cannot set phys_material (%s)" % (r["name"], ex))
                else:
                    warn("%s: physical material PM_Roam_%s not found" % (r["name"], pm_name))
            L.save(mi)
            ok += 1
            if r["slot"]:
                slot_map[r["slot"]] = "%s/%s" % (fdir, r["name"])
        except Exception as ex:  # noqa: BLE001
            bad.append("%s (%s)" % (r["name"], ex))
            unreal.log_error("MAT_ERR instance %s: %s" % (r["name"], ex))
    with open(SLOT_MAP_PATH, "w", encoding="utf-8") as fh:
        json.dump(slot_map, fh, indent=1, sort_keys=True)
    log("instances: ok=%d failed=%d slot_map=%d entries" % (ok, len(bad), len(slot_map)))
    if bad:
        warn("instance failures: %s" % bad[:12])
    return "ok=%d failed=%d" % (ok, len(bad))
