"""Creates the settlement-kit material instances that Tools/ue/materials_instances*.py do not provide (agent P1 'props').

Slots used by Exports/Settlements/*.json without an instance: M_Bld_Metal, M_Bld_Neon, M_Bld_PaintBlue, M_Bld_PaintRed, M_Bld_PaintWhite, M_Bld_Window
(+ M_Bld_Rubber, listed in Docs/Kits/settlements_kit.md).  Instances go to /Game/Forza/Materials/Instances/MI_Bld_* (the same folder / naming
convention as the materials agent, so props_import.py finds them by slot name).  Idempotent.  Editor job:
    powershell -NoProfile -ExecutionPolicy Bypass -File Tools/ue/ue_job.ps1 Tools/ue/props_materials_fix.py
Parents: flat colour slots -> M_Roam_Roadside (BaseColor / Metallic / Roughness / emission); window -> M_Roam_Glass_Building.
The window is deliberately nearly opaque (the buildings are hollow shells without interiors: a transparent pane would show the back faces).
"""
import os
import sys

import unreal

_HERE = unreal.Paths.project_dir().replace("\\", "/") + "Tools/ue"
if _HERE not in sys.path:
    sys.path.insert(0, _HERE)
import materials_lib as L  # noqa: E402  (read-only use of the materials agent's helper)

INST = L.MAT_ROOT + "/Instances"


def srgb(h, a=1.0):
    h = h.lstrip("#")
    r, g, b = [int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]

    def f(c):
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    return (f(r), f(g), f(b), a)


def flat(name, hexcol, metal, rough, emission=None, note=""):
    sc = {"Metallic": metal, "Roughness": rough, "ColorBreakup": 0.12, "RoughnessBreakup": 0.2, "VertexColorTint": 1.0, "SpecularBase": 0.5, "RetroReflective": 0.0}
    vec = {"BaseColor": srgb(hexcol)}
    if emission:
        sc.update(EmissionMode=emission[2], EmissiveIntensity=emission[1])
        vec["EmissiveColor"] = srgb(emission[0])
    return (name, L.MAT_ROOT + "/M_Roam_Roadside", sc, vec, note)


SPECS = [
    flat("MI_Bld_PaintWhite", "#ecece8", 0.0, 0.55, note="white paint (boats, lighthouse, diner, barn trim)"),
    flat("MI_Bld_PaintRed", "#b3211a", 0.0, 0.5, note="red paint (barn, lighthouse stripes, diner)"),
    flat("MI_Bld_PaintBlue", "#2a5da6", 0.0, 0.5, note="blue paint (harbour hut doors, boats)"),
    flat("MI_Bld_Metal", "#8d9399", 0.85, 0.45, note="galvanised / painted sheet metal, gutters, hardware"),
    flat("MI_Bld_Rubber", "#1b1b1c", 0.0, 0.85, note="rubber (hoses, fenders)"),
    flat("MI_Bld_Neon", "#ff5a78", 0.0, 0.4, emission=("#ff3d66", 18.0, 2.0), note="diner / gas station neon, emissive at night only"),
    ("MI_Bld_Window", L.MAT_ROOT + "/M_Roam_Glass_Building",
     {"WindowGridEnabled": 0.0, "DirtAmount": 0.15, "OpacityFacing": 0.93, "OpacityGrazing": 0.99, "GlassRoughness": 0.06},
     {"GlassColor": (0.045, 0.075, 0.095, 1.0)}, "dark pane of the settlements kit (near opaque: hollow shells)"),
]


def main():
    made = 0
    for name, parent, scalars, vectors, note in SPECS:
        path = INST + "/" + name
        mi = L.new_instance(path, L.load(parent), scalars=scalars, vectors=vectors)
        L.save(mi)
        made += 1
        unreal.log("PROPS_MAT %s <- %s (%s)" % (name, parent.rsplit("/", 1)[1], note))
    unreal.log("PROPS_MAT_DONE %d instances" % made)


main()
