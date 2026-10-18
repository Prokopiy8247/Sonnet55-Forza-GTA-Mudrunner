"""M_Roam_Rain_Streak - unlit translucent streak material for the rain pool of ARoamSkyManager (URoamRainFXComponent).

Parameter "Color": rgb = emissive (the C++ scales it by the current exposure, 1.2 * 2^EV100), a = peak opacity. Opacity tapers across
the width and towards both ends of the plane's UV space so a thin plane reads as a soft streak. Used on an instanced static mesh
(plane), hence used_with_instanced_static_meshes.

Run:  powershell -NoProfile -ExecutionPolicy Bypass -File Tools/ue/ue_job.ps1 Tools/ue/sky_rain_material.py
"""
import os
import sys

import unreal

_HERE = os.path.normpath(unreal.Paths.project_dir() + "Tools/ue")
if _HERE not in sys.path:
    sys.path.insert(0, _HERE)
import materials_lib as L  # noqa: E402
from materials_lib import Graph, MAT_ROOT, MP, new_material  # noqa: E402
import materials_masters as MM  # noqa: E402


def build():
    name = "M_Roam_Rain_Streak"
    m = new_material(MAT_ROOT + "/" + name, blend_mode=unreal.BlendMode.BLEND_TRANSLUCENT, two_sided=True,
                     used_with_instanced_static_meshes=True)
    m.set_editor_property("shading_model", unreal.MaterialShadingModel.MSM_UNLIT)
    g = Graph(m)
    S = "Rain"
    uv = g.texcoord(0)
    color = g.vector("Color", (1.0, 1.0, 1.0, 0.25), S)
    across = g.sat(1.0 - g.abs(uv.r * 2.0 - 1.0))
    along = g.sat(1.0 - g.abs(uv.g_ * 2.0 - 1.0))
    shape = g.pow(across, 1.2) * g.sat(along * 3.0)
    g.out(MP.MP_EMISSIVE_COLOR, color.rgb)
    g.out(MP.MP_OPACITY, g.sat(color["A"] * shape))
    errs = MM.finish(g, name)
    L.log("ROAM_RAIN_MATERIAL errors=%d" % len(errs))
    return errs


build()
