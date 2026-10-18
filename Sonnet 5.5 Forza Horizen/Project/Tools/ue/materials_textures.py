"""Imports the procedural textures (Content/Forza/Textures/Source/<Name>/<Name>_BC|N|ORM|D.png, manifest.json) as uassets.

    /Game/Forza/Textures/<Group>/T_<Name>_BC | _N | _ORM | _D          Group = Terrain | Road | Building | Nature | FX | Roadside

Settings: BC sRGB + mips + streaming (no virtual textures); N = Normal-map compression, sRGB off, flip-green OFF (the generator writes the
DirectX/Unreal convention, green = down); ORM = BC7 linear (R=AO G=Roughness B=Metallic); atlases keep alpha (BC7) and get an alpha-coverage
threshold so masked foliage does not thin out in the mips.  Idempotent: existing assets are only re-imported when the source file changed
(size/mtime recorded in Content/Forza/Textures/_import_state.json) or when `force` is set.

Usage inside the editor (job server):  import materials_textures; materials_textures.import_all(force=False)
"""
import json
import os
import sys

import unreal

_HERE = os.path.dirname(os.path.abspath(globals().get("__file__", unreal.Paths.project_dir() + "Tools/ue/materials_textures.py")))
if _HERE not in sys.path:
    sys.path.insert(0, _HERE)
from materials_lib import ROOT, TEX_ROOT, ea, at, ensure_dir, log, warn, exists  # noqa: E402

SRC = ROOT + "Content/Forza/Textures/Source"
STATE_PATH = ROOT + "Content/Forza/Textures/_import_state.json"
BILLBOARD_SRC = ROOT + "Exports/Roadside/Textures"
FARCARD_SRC = ROOT + "Exports/Nature/Trees/Textures"

GROUP_DIR = {"terrain": "Terrain", "road": "Road", "building": "Building", "nature": "Nature", "fx": "FX"}

# sets whose BC has alpha used as a mask (foliage / flowers / grass cards): alpha coverage preserved in mips
MASKED_ATLASES = {"leaf_atlas_broadleaf", "needle_atlas", "palm_frond_atlas", "grass_blade_atlas", "flower_atlas"}
# sprites / decals that must not wrap
CLAMPED = {"dust_puff_sprite", "smoke_puff_sprite", "road_markings_atlas", "leaf_atlas_broadleaf", "needle_atlas", "palm_frond_atlas",
           "grass_blade_atlas", "flower_atlas"}
EFFECT_GROUP = {"dust_puff_sprite", "smoke_puff_sprite", "rain_streaks", "skid_dirt", "tire_mark"}
HERO_BC7 = {"asphalt_new", "asphalt_worn", "road_markings_atlas", "rock_cliff"}  # BC (colour) as BC7 as well
ALPHA_COVERAGE = 0.45  # masked foliage clip value used by the masters

TC = unreal.TextureCompressionSettings
TG = unreal.TextureGroup


def _load_state():
    try:
        with open(STATE_PATH, "r", encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return {}


def _save_state(st):
    with open(STATE_PATH, "w", encoding="utf-8") as fh:
        json.dump(st, fh, indent=1, sort_keys=True)


def _sig(path):
    s = os.stat(path)
    return "%d:%d" % (s.st_size, int(s.st_mtime))


def _plan(only=None):
    """-> list of dicts {name, kind (BC|N|ORM|D), src, dest_dir, asset, set}"""
    with open(SRC + "/manifest.json", "r", encoding="utf-8") as fh:
        man = json.load(fh)
    items = []
    for s in man["sets"]:
        name = s["name"]
        if only and name not in only:
            continue
        group = GROUP_DIR.get(s.get("category"), "Misc")
        for kind in ("BC", "N", "ORM", "D"):
            if kind not in s["files"]:
                continue
            src = "%s/%s/%s_%s.png" % (SRC, name, name, kind)
            if not os.path.exists(src):
                warn("missing source %s" % src)
                continue
            items.append({"set": name, "kind": kind, "src": src, "dest_dir": "%s/%s" % (TEX_ROOT, group),
                          "asset": "T_%s_%s" % (name, kind)})
    if not only or "_billboards" in only:
        for ch in "ABC":
            src = "%s/T_RS_BillboardAd_%s.png" % (BILLBOARD_SRC, ch)
            if os.path.exists(src):
                items.append({"set": "billboard_" + ch, "kind": "BC", "src": src, "dest_dir": TEX_ROOT + "/Roadside",
                              "asset": "T_RS_BillboardAd_" + ch})
    if not only or "_farcards" in only:
        if os.path.isdir(FARCARD_SRC):
            for fn in sorted(os.listdir(FARCARD_SRC)):
                if fn.startswith("T_tree_") and fn.endswith("_Far.png"):
                    tid = fn[len("T_"):-len("_Far.png")]  # tree_oak_a
                    items.append({"set": "farcard_" + tid, "kind": "BC", "src": FARCARD_SRC + "/" + fn, "dest_dir": TEX_ROOT + "/Nature",
                                  "asset": "T_" + tid + "_Far"})
    return items


def configure(tex, it):
    """Apply the import settings to a Texture2D (idempotent)."""
    kind, setname = it["kind"], it["set"]
    tex.set_editor_property("virtual_texture_streaming", False)
    tex.set_editor_property("never_stream", False)
    tex.set_editor_property("flip_green_channel", False)
    tex.set_editor_property("mip_gen_settings", unreal.TextureMipGenSettings.TMGS_FROM_TEXTURE_GROUP)
    if kind == "BC":
        tex.set_editor_property("srgb", True)
        tex.set_editor_property("compression_settings", TC.TC_BC7 if (setname in HERO_BC7 or setname in MASKED_ATLASES) else TC.TC_DEFAULT)
        tex.set_editor_property("lod_group", TG.TEXTUREGROUP_EFFECTS if setname in EFFECT_GROUP else TG.TEXTUREGROUP_WORLD)
    elif kind == "N":
        tex.set_editor_property("srgb", False)
        tex.set_editor_property("compression_settings", TC.TC_NORMALMAP)
        tex.set_editor_property("lod_group", TG.TEXTUREGROUP_WORLD_NORMAL_MAP)
    else:  # ORM / D: linear data
        tex.set_editor_property("srgb", False)
        tex.set_editor_property("compression_settings", TC.TC_BC7)
        tex.set_editor_property("lod_group", TG.TEXTUREGROUP_WORLD)
    if setname in CLAMPED or setname.startswith("farcard_") or setname.startswith("billboard_"):
        tex.set_editor_property("address_x", unreal.TextureAddress.TA_CLAMP)
        tex.set_editor_property("address_y", unreal.TextureAddress.TA_CLAMP)
    else:
        tex.set_editor_property("address_x", unreal.TextureAddress.TA_WRAP)
        tex.set_editor_property("address_y", unreal.TextureAddress.TA_WRAP)
    if (setname in MASKED_ATLASES or setname.startswith("farcard_")) and kind == "BC":
        tex.set_editor_property("alpha_coverage_thresholds", unreal.Vector4(0.0, 0.0, 0.0, ALPHA_COVERAGE))
        tex.set_editor_property("compression_no_alpha", False)
        tex.set_editor_property("do_scale_mips_for_alpha_coverage", True)
    if kind == "D":
        tex.set_editor_property("mip_gen_settings", unreal.TextureMipGenSettings.TMGS_FROM_TEXTURE_GROUP)


def _sig_props(tex):
    keys = ("compression_settings", "srgb", "lod_group", "address_x", "address_y", "flip_green_channel", "virtual_texture_streaming",
            "never_stream", "mip_gen_settings", "alpha_coverage_thresholds", "do_scale_mips_for_alpha_coverage")
    return tuple(str(tex.get_editor_property(k)) for k in keys)


def import_all(force=False, only=None, chunk=16):
    """Import (or refresh settings of) every texture. `only` = set of manifest names. Returns number of imported assets."""
    ensure_dir(TEX_ROOT)
    state = _load_state()
    items = _plan(only)
    todo, have = [], []
    for it in items:
        path = "%s/%s" % (it["dest_dir"], it["asset"])
        sig = _sig(it["src"])
        it["path"], it["sig"] = path, sig
        if force or not exists(path) or state.get(path) != sig:
            if exists(path) and not force and path not in state:
                state[path] = sig  # asset exists but no record: trust it (fresh clone)
                have.append(it)
            else:
                todo.append(it)
        else:
            have.append(it)
    log("textures: %d planned, %d to import, %d present" % (len(items), len(todo), len(have)))
    n_done = 0
    for i in range(0, len(todo), chunk):
        part = todo[i:i + chunk]
        tasks = []
        for it in part:
            ensure_dir(it["dest_dir"])
            t = unreal.AssetImportTask()
            t.set_editor_property("filename", it["src"])
            t.set_editor_property("destination_path", it["dest_dir"])
            t.set_editor_property("destination_name", it["asset"])
            t.set_editor_property("automated", True)
            t.set_editor_property("replace_existing", True)
            t.set_editor_property("replace_existing_settings", True)
            t.set_editor_property("save", False)
            t.set_editor_property("factory", unreal.TextureFactory())
            tasks.append(t)
        at.import_asset_tasks(tasks)
        for it, t in zip(part, tasks):
            tex = ea.load_asset(it["path"])
            if tex is None:
                warn("IMPORT FAILED %s" % it["src"])
                continue
            configure(tex, it)
            ea.save_loaded_asset(tex)
            state[it["path"]] = it["sig"]
            n_done += 1
        _save_state(state)
        log("textures imported %d/%d" % (min(i + chunk, len(todo)), len(todo)))
    # settings refresh for textures that were already there (cheap)
    for it in have:
        tex = ea.load_asset(it["path"])
        if tex is None:
            continue
        before = _sig_props(tex)
        configure(tex, it)
        after = _sig_props(tex)
        if before != after:
            ea.save_loaded_asset(tex)
    _save_state(state)
    return n_done


def tex_path(setname, kind):
    """Asset path (without object suffix) of an imported texture."""
    if setname.startswith("farcard_"):
        return "%s/Nature/T_%s_Far" % (TEX_ROOT, setname[len("farcard_"):])
    man = tex_path._man if hasattr(tex_path, "_man") else None
    if man is None:
        with open(SRC + "/manifest.json", "r", encoding="utf-8") as fh:
            man = {s["name"]: s for s in json.load(fh)["sets"]}
        tex_path._man = man
    group = GROUP_DIR[man[setname]["category"]]
    return "%s/%s/T_%s_%s" % (TEX_ROOT, group, setname, kind)


def tile_metres(setname):
    """Real-world edge length(s) of one tile in metres (float or (w, h))."""
    tile_metres._man = getattr(tile_metres, "_man", None)
    if tile_metres._man is None:
        with open(SRC + "/manifest.json", "r", encoding="utf-8") as fh:
            tile_metres._man = {s["name"]: s for s in json.load(fh)["sets"]}
    t = tile_metres._man[setname].get("tile_metres", 1.0)
    return tuple(t) if isinstance(t, list) else float(t)


def sets_of_groups(groups):
    """Set names of the manifest whose category is in `groups` (e.g. ['road', 'fx']); 'billboards' adds the roadside ad textures."""
    with open(SRC + "/manifest.json", "r", encoding="utf-8") as fh:
        man = json.load(fh)
    out = set()
    for s in man["sets"]:
        if s.get("category") in groups:
            out.add(s["name"])
    if "billboards" in groups:
        out.add("_billboards")
    if "farcards" in groups or "nature" in groups:
        out.add("_farcards")
    return out
