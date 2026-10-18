"""Registry of the master materials + helpers shared by the materials_m_*.py builders.

Each builder module exposes BUILDERS = {"M_Name": function()}; `build_all(only)` runs them (idempotent: an existing material is wiped
and rebuilt in place, so instances keep their parent and overrides).  A master that fails to compile is reported, never silently skipped.
"""
import importlib
import os
import sys
import time
import traceback

import unreal

_HERE = os.path.dirname(os.path.abspath(globals().get("__file__", unreal.Paths.project_dir() + "Tools/ue/materials_masters.py")))
if _HERE not in sys.path:
    sys.path.insert(0, _HERE)
import materials_lib as L  # noqa: E402
from materials_lib import MAT_ROOT, MP, E, Graph, load, log, new_material, save, warn  # noqa: E402
from materials_textures import tex_path  # noqa: E402

MPC_PATH = MAT_ROOT + "/MPC_Roam_World"
MODULES = ["materials_m_road", "materials_m_surface", "materials_m_nature", "materials_m_fx"]

# ------------------------------------------------------------------------------------------------------------------------------
# HLSL snippets shared by several masters (Custom nodes are straight-line code: helpers are macros)
# ------------------------------------------------------------------------------------------------------------------------------
NIGHT_HLSL = """
float nightF = (NightOv >= 0.0) ? saturate(NightOv) : saturate((1.0 - smoothstep(4.5, 7.0, Hour)) + smoothstep(18.5, 21.0, Hour));
"""


def mpc():
    return load(MPC_PATH)


class Common(object):
    """MPC readers + coordinates that nearly every master needs, built once per graph."""

    def __init__(self, g, wanted=("Wetness", "PuddleAmount", "RainIntensity", "SnowAmount", "DustAmount")):
        self.g = g
        c = mpc()
        self.v = {n: g.mpc(c, n) for n in wanted}
        self._mpc = c

    def get(self, name):
        if name not in self.v:
            self.v[name] = self.g.mpc(self._mpc, name)
        return self.v[name]


def noise_tex(g, uv, group="Noise"):
    """Tileable perlin noise (R perlin fBm, G finer perlin, B worley billow, A ridged) -> RGBA E."""
    return g.texture("NoiseTex", tex_path("tileable_perlin_noise", "D"), "linear", uv, group)["RGBA"]


def pbr_texture_paths(setname):
    """(BC, N, ORM) asset paths of an imported texture set."""
    return (tex_path(setname, "BC"), tex_path(setname, "N"), tex_path(setname, "ORM"))


def mpc_nodes(g, collection, names):
    """dict name -> CollectionParameter E for the listed MPC scalars/vectors."""
    return {n: g.mpc(collection, n) for n in names}


def pbr_samples(g, uv_a, uv_b, paths, group="Surface", switch="AntiTile", prefix=""):
    """Sample BC/N/ORM at uv_a and (if uv_b) at uv_b - the second set is selected by the static switch `switch` (off = same as set a).
    Returns dict of E: bc_a, n_a, orm_a, bc_b, n_b, orm_b (rgb outputs) and bc_alpha (alpha of set a)."""
    p_bc, p_n, p_orm = paths
    bca = g.texture(prefix + "BaseColorTex", p_bc, "color", uv_a, group)
    na = g.texture(prefix + "NormalTex", p_n, "normal", uv_a, group)
    oa = g.texture(prefix + "ORMTex", p_orm, "linear", uv_a, group)
    out = {"bc_a": bca["RGB"], "n_a": na["RGB"], "orm_a": oa["RGB"], "bc_alpha": bca["A"]}
    if uv_b is None:
        out.update(bc_b=out["bc_a"], n_b=out["n_a"], orm_b=out["orm_a"])
        return out
    bcb = g.texture(prefix + "BaseColorTex", p_bc, "color", uv_b, group)
    nb = g.texture(prefix + "NormalTex", p_n, "normal", uv_b, group)
    ob = g.texture(prefix + "ORMTex", p_orm, "linear", uv_b, group)
    out["bc_b"] = g.switch(switch, True, bcb["RGB"], out["bc_a"], group)
    out["n_b"] = g.switch(switch, True, nb["RGB"], out["n_a"], group)
    out["orm_b"] = g.switch(switch, True, ob["RGB"], out["orm_a"], group)
    return out


def finish(g, name, m=None):
    """Recompile and report. Returns list of error strings (empty = compiled)."""
    m = m if m is not None else g.m
    errs = g.done()
    if errs:
        warn("%s: %d COMPILE ERROR(S)" % (name, len(errs)))
        for e in errs[:3]:
            unreal.log_error("MAT_ERR %s: %s" % (name, e[:1800]))
    else:
        stats = None
        try:
            stats = L.mel.get_statistics(m)
        except Exception:  # noqa: BLE001
            pass
        log("%s compiled OK%s" % (name, (" (ps instr %d, samplers %d, nodes %d)" % (stats.num_pixel_shader_instructions, stats.num_samplers, g._count)) if stats else ""))
    save(m)
    return errs


def build_all(only=None):
    """Build every master (or those in `only`). Returns 'ok=N failed=[...]'."""
    ok, failed = 0, []
    t0 = time.time()
    for modname in MODULES:
        if not os.path.exists("%s/%s.py" % (_HERE, modname)):
            continue
        try:
            mod = importlib.reload(sys.modules[modname]) if modname in sys.modules else importlib.import_module(modname)
            builders = mod.BUILDERS
        except Exception:  # noqa: BLE001
            unreal.log_error("MAT_ERR cannot load builder module %s | %s" % (modname, traceback.format_exc()))
            failed.append(modname)
            continue
        for name, fn in builders.items():
            if only and name not in only:
                continue
            t1 = time.time()
            try:
                errs = fn()
                if errs:
                    failed.append(name)
                else:
                    ok += 1
            except Exception:  # noqa: BLE001
                unreal.log_error("MAT_ERR builder %s\n%s" % (name, traceback.format_exc()))
                failed.append(name)
            log("builder %s %.1fs" % (name, time.time() - t1))
    return "ok=%d failed=%s (%.0fs)" % (ok, failed, time.time() - t0)
