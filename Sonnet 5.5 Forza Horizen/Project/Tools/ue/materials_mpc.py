"""MPC_Roam_World - the global weather / time / wind state read by every world material.

Writers: the sky / weather agent (RoamSkyManager) through
    UKismetMaterialLibrary::SetScalarParameterValue(World, MPC_Roam_World, "Wetness", v)   /   SetVectorParameterValue(..., "WindDirection", ...)
Defaults are a dry, calm, daytime state so every material looks right without any writer.
"""
import os
import sys

import unreal

_HERE = os.path.dirname(os.path.abspath(globals().get("__file__", unreal.Paths.project_dir() + "Tools/ue/materials_mpc.py")))
if _HERE not in sys.path:
    sys.path.insert(0, _HERE)
from materials_lib import MAT_ROOT, at, ea, ensure_dir, exists, load, log, save  # noqa: E402

MPC_PATH = MAT_ROOT + "/MPC_Roam_World"

# name -> (default, meaning)
SCALARS = [
    ("Wetness", 0.0, "0..1 road/building surface wetness (RoamTimeWeatherSubsystem::GetWetness)"),
    ("PuddleAmount", 0.0, "0..1 puddle coverage; roads fall back to Wetness^2*0.5 if this stays 0"),
    ("RainIntensity", 0.0, "0..1 rain strength: ripples on wet roads, drips; 0 = no ripples"),
    ("SnowAmount", 0.0, "0..1 snow cover (roads keep the lanes clear, shoulders/rocks/roofs whiten)"),
    ("DustAmount", 0.0, "0..1 dust on dry surfaces (desert/dirt)"),
    ("TimeOfDay", 12.0, "game hour 0..24 (night windows, street lamps, lights)"),
    ("NightFactor", -1.0, "0..1 night blend; NEGATIVE = derive from TimeOfDay (dusk 18.5-21, dawn 4.5-7)"),
    ("WindStrength", 0.35, "0..1 sway amplitude multiplier for foliage/grass"),
    ("WindSpeed", 5.0, "m/s, sway frequency and gust scrolling"),
    ("FoliageSeason", 0.0, "0..1 blend of SeasonTint into foliage/grass (0 = summer)"),
    ("Headlights", 1.0, "0..1 player headlights on: scales the retro-reflective response of road signs / reflectors at night (the vehicle visuals may write it)"),
    ("GlobalTime", 0.0, "optional seconds (materials normally use the Time node; use to freeze/scrub in tests)"),
]
VECTORS = [
    ("WindDirection", (1.0, 0.0, 0.0, 0.0), "xyz = unit wind direction in world space (w unused)"),
    ("SeasonTint", (1.0, 1.0, 1.0, 1.0), "rgb multiplier for foliage/grass colour (autumn = warm), a unused"),
]


def build():
    ensure_dir(MAT_ROOT)
    if exists(MPC_PATH):
        mpc = load(MPC_PATH)
    else:
        mpc = at.create_asset("MPC_Roam_World", MAT_ROOT, unreal.MaterialParameterCollection, unreal.MaterialParameterCollectionFactoryNew())
    # KEEP EXISTING PARAMETERS: every CollectionParameter material node stores the parameter GUID, so recreating the parameters
    # (new GUIDs) makes every material that reads this collection fail with "CollectionParameter has invalid parameter None"
    # (the world / road / car masters then render as the checkerboard). Existing entries (and their GUIDs) are copied through
    # untouched, only parameters that do not exist yet are appended.
    sps = list(mpc.get_editor_property("scalar_parameters"))
    vps = list(mpc.get_editor_property("vector_parameters"))
    have_s = {str(p.get_editor_property("parameter_name")) for p in sps}
    have_v = {str(p.get_editor_property("parameter_name")) for p in vps}
    added = []
    for name, default, _ in SCALARS:
        if name in have_s:
            continue
        p = unreal.CollectionScalarParameter()
        p.set_editor_property("parameter_name", name)
        p.set_editor_property("default_value", float(default))
        sps.append(p)
        added.append(name)
    for name, default, _ in VECTORS:
        if name in have_v:
            continue
        p = unreal.CollectionVectorParameter()
        p.set_editor_property("parameter_name", name)
        p.set_editor_property("default_value", unreal.LinearColor(*default))
        vps.append(p)
        added.append(name)
    if added:
        mpc.set_editor_property("scalar_parameters", sps)
        mpc.set_editor_property("vector_parameters", vps)
        save(mpc)
    log("MPC_Roam_World: %d scalars, %d vectors (kept existing GUIDs; added %s)" % (len(sps), len(vps), added or "none"))
    return mpc
