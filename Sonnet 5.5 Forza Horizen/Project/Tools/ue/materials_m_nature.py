"""Nature masters: M_Roam_Foliage_Masked (leaf / needle / palm atlases), M_Roam_Bark, M_Roam_Grass_Blade (grass + flowers), M_Roam_Rock,
M_Roam_Tree_Far (distance cards).

Tree-kit contract (Docs/Kits/nature_trees.md): vertex colour (linear) R = branch flex, G = leaf flutter, B = baked AO;
leaf / needle / palm cards use ONE of FOUR U strips per element (u in [k/4,(k+1)/4], v along the leaf, base v=1 in UE) -> `StripMode`
turns strip k into atlas cell (AtlasFirstCell + k); plain cards (UV 0..1 over the whole card, grass / flowers) pick a cell with
AtlasCell or, with RandomCells, per instance from [AtlasFirstCell, AtlasFirstCell + CellCount).
"""
import os
import sys

import unreal

_HERE = os.path.dirname(os.path.abspath(globals().get("__file__", unreal.Paths.project_dir() + "Tools/ue/materials_m_nature.py")))
if _HERE not in sys.path:
    sys.path.insert(0, _HERE)
import materials_lib as L  # noqa: E402
from materials_lib import Graph, MAT_ROOT, MP, load, new_material  # noqa: E402
import materials_masters as MM  # noqa: E402
import materials_textures as T  # noqa: E402

# ------------------------------------------------------------------------------------------------------------------------------
# wind: vertex-stage offset (world space, cm).  Hierarchical like the kit: R^2 sways the branch, G flutters the leaf.
# ------------------------------------------------------------------------------------------------------------------------------
WIND = """
float3 dirW = float3(WDir.x, WDir.y, 0.0);
float dl = length(dirW);
dirW = (dl > 1e-3) ? dirW / dl : float3(1.0, 0.0, 0.0);
float ph = OPos.x * 0.0123 + OPos.y * 0.0171 + PerInst * 6.2831;
float spd = 0.6 + 0.08 * WSpeed;
float gust = 0.65 + 0.35 * sin(Tsec * 0.31 * spd + dot(WPos.xy, dirW.xy) * 0.0031);
float amp = WStr * gust * (0.35 + 0.065 * WSpeed) * WindOn;
float m = lerp(VR, saturate(1.0 - TC.y), UVMask);
float sw = sin(Tsec * SwayFreq * spd * 6.2831 + ph) + 0.35 * sin(Tsec * SwayFreq * spd * 10.7 + ph * 1.9 + 1.3);
float f1 = sin(Tsec * FlutFreq * spd * 6.2831 + dot(WPos, float3(0.071, 0.093, 0.117)) + ph * 3.0);
float f2 = sin(Tsec * FlutFreq * spd * 14.1 + dot(WPos, float3(0.113, 0.057, 0.141)) + ph);
float3 off = dirW * (m * m * SwayAmp * (0.35 + sw) * amp);
off += float3(f1 + 0.5 * f2, f2 - 0.5 * f1, 0.5 * (f1 - f2)) * (VG * FlutAmp * amp);
return off;
"""

ATLAS_UV = """
float cols = max(AtlasCols, 1.0);
float rows = max(AtlasRows, 1.0);
float ncell = cols * rows;
float k = 0.0;
float lu = saturate(TC0.x);
float lv = saturate(TC0.y);
float cell = AtlasCell;
if (StripMode > 0.5)
{
    float su = saturate(TC0.x) * 4.0;
    k = floor(min(su, 3.9999));
    lu = saturate(su - k);
    cell = AtlasFirstCell + fmod(k, max(StripCellCount, 1.0));
}
else if (RandomCells > 0.5)
{
    k = floor(saturate(PerInst) * max(CellCount, 1.0) * 0.9999);
    cell = AtlasFirstCell + k;
}
cell = fmod(cell + ncell * 4.0, ncell);
float cc = fmod(cell, cols);
float cr = floor(cell / cols);
lu = clamp(lu, 0.006, 0.994);
lv = clamp(lv, 0.006, 0.994);
Strip = k;
return float2((cc + lu) / cols, (cr + lv) / rows);
"""

FOLIAGE_SHADE = """
float3 col = BC * Tint.rgb;
col *= lerp(float3(1.0, 1.0, 1.0), lerp(VarA.rgb, VarB.rgb, saturate(PerInst)), VarAmt);
col *= 1.0 + (frac(Strip * 0.37 + 0.11) - 0.5) * StripVar;
col *= 1.0 + (Nz.r - 0.5) * 2.0 * PatchAmt;
col = lerp(col, col * SeasonTint.rgb, saturate(SeasonAmt * Season));
float hgt = saturate(1.0 - TC0.y);
float ao = lerp(1.0, saturate(VCb), AOStr);
ao *= lerp(1.0, lerp(0.35, 1.0, hgt), GradAO);
col *= lerp(0.45, 1.0, ao);
float wet = saturate(Wet * WetResp);
col *= lerp(1.0, 0.78, wet);
float snow = saturate((Snow * SnowResp * 1.6 - (1.0 - saturate(VCb)) * 0.6 - (1.0 - Nz.g) * 0.25) * 3.0) * lerp(1.0, hgt, GradAO);
col = lerp(col, float3(0.78, 0.82, 0.90), snow * 0.85);
float dist = distance(CamPos, WPos);
float fade = (FadeEnd > 0.5) ? saturate((FadeEnd * 100.0 - dist) / max((FadeEnd - FadeStart) * 100.0, 1.0)) : 1.0;
Mask = Alpha * fade;
Sss = col * TransCol.rgb * TransAmt;
Normal = normalize(float3(Nrm.xy * NStr, max(Nrm.z, 0.3)));
Rough = saturate(lerp(ORM.g, 1.0, snow) * RoughScale * lerp(1.0, 0.6, wet));
AO = lerp(0.6, 1.0, ao);
Spec = SpecBase;
return col;
"""

BARK_SHADE = """
float3 col = BC * Tint.rgb;
col *= lerp(float3(1.0, 1.0, 1.0), lerp(VarA.rgb, VarB.rgb, saturate(PerInst)), VarAmt);
col *= 1.0 + (Nz.r - 0.5) * 2.0 * PatchAmt;
float lum = dot(col, float3(0.3, 0.59, 0.11));
col = lerp(float3(lum, lum, lum), col, Sat);
float ao = lerp(1.0, saturate(VCb), AOStr);
col *= lerp(0.5, 1.0, ao);
float wet = saturate(Wet * WetResp);
col *= lerp(1.0, 0.7, wet);
float up = saturate(VN.z);
float snow = saturate((Snow * SnowResp * 1.5 - (1.0 - up) * 1.2 + (Nz.g - 0.5) * 0.4) * 3.0);
col = lerp(col, float3(0.78, 0.82, 0.90), snow);
Normal = normalize(float3(Nrm.xy * NStr, max(Nrm.z, 0.3)));
Rough = saturate(lerp(ORM.g * RoughScale, 0.8, snow) * lerp(1.0, 0.7, wet));
AO = lerp(0.55, 1.0, ao) * lerp(1.0, ORM.r, 0.8);
Spec = SpecBase;
return col;
"""

ROCK_SHADE = """
float3 p = WPos * 0.01;
float3 an = pow(abs(VN), Sharp);
an /= max(an.x + an.y + an.z, 1e-4);
float3 sg = float3((VN.x >= 0.0) ? 1.0 : -1.0, (VN.y >= 0.0) ? 1.0 : -1.0, (VN.z >= 0.0) ? 1.0 : -1.0);
// world normal of each planar projection (tangent normal rotated into the projection frame)
float3 tx = float3(Nx.xy * NStr, max(Nx.z, 0.2));
float3 ty = float3(Ny.xy * NStr, max(Ny.z, 0.2));
float3 tz = float3(Nz.xy * NStr, max(Nz.z, 0.2));
float3 nX = float3(sg.x * tx.z, tx.x, -tx.y);
float3 nY = float3(ty.x, sg.y * ty.z, -ty.y);
float3 nZ = float3(tz.x, tz.y, sg.z * tz.z);
float3 nw = normalize(nX * an.x + nY * an.y + nZ * an.z + 1e-5);
float3 col = (BCx * an.x + BCy * an.y + BCz * an.z) * Tint.rgb;
float3 orm = ORMx * an.x + ORMy * an.y + ORMz * an.z;
float rough = orm.g * RoughScale;
float ao = lerp(1.0, orm.r, AOStr);
// macro variation (hides the repetition of the 4 m tile)
float macroN = (Noi.r - 0.5) + (Noi.g - 0.5) * 0.5;
col *= 1.0 + macroN * MacroAmt;
rough = saturate(rough + (Noi.b - 0.5) * 0.15 * MacroAmt);
// slope: up-facing surfaces collect moss, snow
float up = nw.z;
float breakup = (Noi.g * 0.6 + Noi.a * 0.4);
float mossM = smoothstep(MossSlope, MossSlope + 0.25, up + (breakup - 0.5) * 0.5) * MossAmount;
mossM *= saturate(MossHeightNoise + (1.0 - MossHeightNoise) * Noi.r * 1.6);
col = lerp(col, MossCol.rgb * (0.5 + 1.0 * orm.r), mossM * MossOn);
rough = lerp(rough, 0.92, mossM * MossOn);
float snowM = smoothstep(0.30 - Snow * 0.25, 0.78, up + (breakup - 0.5) * 0.35) * saturate(Snow * SnowResp * 1.5);
col = lerp(col, SnowCol.rgb, snowM);
rough = lerp(rough, 0.7, snowM);
float wet = saturate(Wet * WetResp);
col *= lerp(1.0, 0.62, wet * (1.0 - snowM));
rough = lerp(rough, rough * 0.45, wet * (1.0 - snowM));
float dustM = saturate(Dust * 1.2 * (0.4 + Noi.b)) * (1.0 - snowM) * (1.0 - wet);
col = lerp(col, DustCol.rgb * (0.6 + col.g), dustM * 0.5);
Rough = saturate(rough);
AO = ao;
// slope / snow smooth the bump
NormalWS = normalize(lerp(nw, VN, snowM * 0.6 + mossM * MossOn * 0.3));
return col;
"""

SOLID_SHADE = """
float3 col = BaseCol.rgb;
float rnd = lerp(saturate(PerInst), saturate(VCa), VCAmt);
col *= lerp(float3(1.0, 1.0, 1.0), lerp(VarA.rgb, VarB.rgb, rnd), VarAmt);
col *= 1.0 + (Nz.r - 0.5) * 2.0 * PatchAmt;
col = lerp(col, col * SeasonTint.rgb, saturate(SeasonAmt * Season));
float ao = lerp(1.0, saturate(VCb), AOStr);
col *= lerp(0.35, 1.0, ao);
float wet = saturate(Wet * WetResp);
col *= lerp(1.0, 0.8, wet);
float snow = saturate((Snow * SnowResp * 1.6 - (1.0 - saturate(VCb)) * 0.6 - (1.0 - Nz.g) * 0.25) * 3.0);
col = lerp(col, float3(0.78, 0.82, 0.90), snow * 0.85);
Sss = col * TransCol.rgb * TransAmt;
Rough = saturate(lerp(RoughBase, 1.0, snow) * lerp(1.0, 0.6, wet));
AO = lerp(0.6, 1.0, ao);
return col;
"""


def _scalar_params(g, group, defs):
    return {k: g.scalar(k, d, group, lo, hi) for k, (d, lo, hi) in defs.items()}


def _wind_node(g, vr, vg, tc, uv_mask, p, mp, name="WindWPO"):
    """Vertex-stage Custom node -> float3 offset."""
    ins = {"VR": vr, "VG": vg, "TC": tc, "UVMask": uv_mask, "WPos": g.world_pos()["XYZ"], "OPos": g.node("ObjectPositionWS"),
           "PerInst": g.node("PerInstanceRandom"), "Tsec": g.time(), "WDir": mp["WindDirection"], "WStr": mp["WindStrength"],
           "WSpeed": mp["WindSpeed"], "SwayAmp": p["SwayAmp"], "FlutAmp": p["FlutAmp"], "SwayFreq": p["SwayFreq"], "FlutFreq": p["FlutFreq"],
           "WindOn": p["WindOn"]}
    return g.custom(WIND, ins, out="float3", desc=name)


def _wind_params(g, defaults):
    W = "Wind"
    return {
        "SwayAmp": g.scalar("SwayAmplitude", defaults.get("sway", 45.0), W, 0, 200),
        "FlutAmp": g.scalar("FlutterAmplitude", defaults.get("flutter", 6.0), W, 0, 40),
        "SwayFreq": g.scalar("SwayFrequency", 0.35, W, 0.05, 2),
        "FlutFreq": g.scalar("FlutterFrequency", 1.4, W, 0.1, 6),
        "WindOn": g.scalar("WindEnabled", 1.0, W, 0, 1),
    }


# ------------------------------------------------------------------------------------------------------------------------------
def build_foliage(name="M_Roam_Foliage_Masked", grass=False, atlas="leaf_atlas_broadleaf", wind_defaults=None, fade_end=0.0, name_desc=""):
    """Masked, two-sided foliage master (also used as grass / flower master with grass=True: UV-height wind + AO gradient)."""
    m = new_material(MAT_ROOT + "/" + name,
                     blend_mode=unreal.BlendMode.BLEND_MASKED, two_sided=True,
                     shading_model=unreal.MaterialShadingModel.MSM_TWO_SIDED_FOLIAGE,
                     opacity_mask_clip_value=0.45, used_with_nanite=True, used_with_instanced_static_meshes=True,
                     max_world_position_offset_displacement=140.0)
    g = Graph(m)
    mpc_obj = load(MM.MPC_PATH)
    A, CL, WX, FD = "Atlas", "Colour", "Weather", "Fade"
    paths = MM.pbr_texture_paths(atlas)
    # --- parameters
    cols_rows = {"leaf_atlas_broadleaf": (4, 4), "needle_atlas": (4, 4), "palm_frond_atlas": (2, 2), "grass_blade_atlas": (4, 2), "flower_atlas": (2, 2)}[atlas]
    p = {
        "AtlasCols": g.scalar("AtlasColumns", cols_rows[0], A, 1, 8),
        "AtlasRows": g.scalar("AtlasRows", cols_rows[1], A, 1, 8),
        "StripMode": g.scalar("StripMode", 0.0 if grass else 1.0, A, 0, 1),
        "AtlasFirstCell": g.scalar("AtlasFirstCell", 12.0 if atlas == "leaf_atlas_broadleaf" else 0.0, A, 0, 31),
        "AtlasCell": g.scalar("AtlasCell", 0.0, A, 0, 31),
        "RandomCells": g.scalar("RandomCells", 1.0 if grass else 0.0, A, 0, 1),
        "CellCount": g.scalar("CellCount", 4.0, A, 1, 16),
        "StripCellCount": g.scalar("StripCellCount", 4.0, A, 1, 4),
        "NStr": g.scalar("NormalStrength", 0.6, CL, 0, 2),
        "RoughScale": g.scalar("RoughnessScale", 1.0, CL, 0, 2),
        "SpecBase": g.scalar("SpecularBase", 0.2, CL, 0, 1),
        "VarAmt": g.scalar("VariationAmount", 0.8, CL, 0, 1),
        "StripVar": g.scalar("StripVariation", 0.25, CL, 0, 1),
        "PatchAmt": g.scalar("PatchVariation", 0.25 if grass else 0.0, CL, 0, 1),
        "SeasonAmt": g.scalar("SeasonAmount", 0.0, CL, 0, 1),
        "AOStr": g.scalar("AOStrength", 1.0, CL, 0, 1),
        "GradAO": g.scalar("HeightAOGradient", 1.0 if grass else 0.0, CL, 0, 1),
        "TransAmt": g.scalar("TranslucencyAmount", 0.35, CL, 0, 1),
        "WetResp": g.scalar("WetnessResponse", 1.0, WX, 0, 1),
        "SnowResp": g.scalar("SnowResponse", 0.08 if grass else 0.3, WX, 0, 1),
        "FadeStart": g.scalar("FadeStartDistance", max(fade_end * 0.7, 0.0), FD, 0, 500),
        "FadeEnd": g.scalar("FadeEndDistance", fade_end, FD, 0, 500),
        "UVMask": g.scalar("WindMaskFromUV", 1.0 if grass else 0.0, "Wind", 0, 1),
    }
    p.update(_wind_params(g, wind_defaults or {}))
    tint = g.vector("Tint", (1, 1, 1, 1), CL)
    var_a = g.vector("VariationTintA", (0.88, 0.95, 0.8, 1), CL)
    var_b = g.vector("VariationTintB", (1.12, 1.05, 0.9, 1), CL)
    trans_col = g.vector("TranslucencyColor", (0.55, 0.85, 0.2, 1), CL)
    mp = MM.mpc_nodes(g, mpc_obj, ["WindDirection", "WindStrength", "WindSpeed", "Wetness", "SnowAmount", "FoliageSeason", "SeasonTint"])
    uv0 = g.texcoord(0)
    wp = g.world_pos()
    per_inst = g.node("PerInstanceRandom")
    nz = MM.noise_tex(g, wp["XY"] * (0.01 / 20.0))
    uvc = g.custom(ATLAS_UV, {"TC0": uv0, "AtlasCols": p["AtlasCols"], "AtlasRows": p["AtlasRows"], "StripMode": p["StripMode"],
                              "AtlasFirstCell": p["AtlasFirstCell"], "AtlasCell": p["AtlasCell"], "RandomCells": p["RandomCells"],
                              "CellCount": p["CellCount"], "StripCellCount": p["StripCellCount"], "PerInst": per_inst}, out="float2", extra={"Strip": "float"}, desc="AtlasUV")
    bc = g.texture("AtlasBC", paths[0], "color", uvc, "Atlas")
    nm = g.texture("AtlasN", paths[1], "normal", uvc, "Atlas")
    orm = g.texture("AtlasORM", paths[2], "linear", uvc, "Atlas")
    vc = g.vertex_color()
    shade_in = {
        "BC": bc["RGB"], "Alpha": bc["A"], "Nrm": nm["RGB"], "ORM": orm["RGB"], "VCb": vc["B"], "WPos": wp["XYZ"], "CamPos": g.camera_pos(),
        "PerInst": per_inst, "Strip": uvc["Strip"], "TC0": uv0, "Nz": nz, "Wet": mp["Wetness"], "Snow": mp["SnowAmount"], "Season": mp["FoliageSeason"],
        "SeasonTint": mp["SeasonTint"], "Tint": tint, "VarA": var_a, "VarB": var_b, "TransCol": trans_col,
    }
    for k in ("VarAmt", "StripVar", "PatchAmt", "SeasonAmt", "AOStr", "GradAO", "TransAmt", "NStr", "RoughScale", "SpecBase", "WetResp", "SnowResp",
              "FadeStart", "FadeEnd"):
        shade_in[k] = p[k]
    sh = g.custom(FOLIAGE_SHADE, shade_in, out="float3",
                  extra={"Mask": "float", "Sss": "float3", "Normal": "float3", "Rough": "float", "AO": "float", "Spec": "float"}, desc="FoliageShade")
    g.out(MP.MP_BASE_COLOR, sh)
    g.out(MP.MP_OPACITY_MASK, sh["Mask"])
    g.out(MP.MP_NORMAL, sh["Normal"])
    g.out(MP.MP_ROUGHNESS, sh["Rough"])
    g.out(MP.MP_AMBIENT_OCCLUSION, sh["AO"])
    g.out(MP.MP_SPECULAR, sh["Spec"])
    g.out(MP.MP_SUBSURFACE_COLOR, sh["Sss"])
    wind = _wind_node(g, vc["R"], vc["G"], uv0, p["UVMask"], p, mp)
    g.out(MP.MP_WORLD_POSITION_OFFSET, wind)
    return MM.finish(g, name)


def build_grass():
    return build_foliage("M_Roam_Grass_Blade", grass=True, atlas="grass_blade_atlas", wind_defaults={"sway": 22.0, "flutter": 3.0}, fade_end=90.0)


def build_flower():
    return build_foliage("M_Roam_Flower", grass=True, atlas="flower_atlas", wind_defaults={"sway": 14.0, "flutter": 2.0}, fade_end=70.0)


def build_foliage_solid():
    """Opaque two-sided modelled foliage (ground-cover kit: bush leaves, grass blades, reeds, crops, petals) and plain-colour plant parts (berries,
    cactus skin / spines / fruit, flower centres): colour parameters instead of an atlas, wind + AO + per-element random from the vertex colour
    (R flex, G flutter, B AO, A random 0..1)."""
    name = "M_Roam_Foliage_Solid"
    m = new_material(MAT_ROOT + "/" + name, two_sided=True, shading_model=unreal.MaterialShadingModel.MSM_TWO_SIDED_FOLIAGE, used_with_nanite=True,
                     used_with_instanced_static_meshes=True, max_world_position_offset_displacement=140.0)
    g = Graph(m)
    mpc_obj = load(MM.MPC_PATH)
    CL, WX = "Colour", "Weather"
    p = {
        "RoughBase": g.scalar("Roughness", 0.6, CL, 0, 1),
        "SpecBase": g.scalar("SpecularBase", 0.3, CL, 0, 1),
        "Metal": g.scalar("Metallic", 0.0, CL, 0, 1),
        "VarAmt": g.scalar("VariationAmount", 0.8, CL, 0, 1),
        "VCAmt": g.scalar("UseVertexRandom", 1.0, CL, 0, 1),
        "PatchAmt": g.scalar("PatchVariation", 0.2, CL, 0, 1),
        "SeasonAmt": g.scalar("SeasonAmount", 0.0, CL, 0, 1),
        "AOStr": g.scalar("AOStrength", 1.0, CL, 0, 1),
        "TransAmt": g.scalar("TranslucencyAmount", 0.3, CL, 0, 1),
        "WetResp": g.scalar("WetnessResponse", 1.0, WX, 0, 1),
        "SnowResp": g.scalar("SnowResponse", 0.3, WX, 0, 1),
        "UVMask": g.scalar("WindMaskFromUV", 0.0, "Wind", 0, 1),
    }
    p.update(_wind_params(g, {"sway": 25.0, "flutter": 4.0}))
    base = g.vector("BaseColor", (0.1, 0.3, 0.05, 1), CL)
    var_a = g.vector("VariationTintA", (0.8, 0.92, 0.75, 1), CL)
    var_b = g.vector("VariationTintB", (1.2, 1.1, 1.0, 1), CL)
    trans_col = g.vector("TranslucencyColor", (0.55, 0.8, 0.2, 1), CL)
    mp = MM.mpc_nodes(g, mpc_obj, ["WindDirection", "WindStrength", "WindSpeed", "Wetness", "SnowAmount", "FoliageSeason", "SeasonTint"])
    uv0 = g.texcoord(0)
    wp = g.world_pos()
    nz = MM.noise_tex(g, wp["XY"] * (0.01 / 20.0))
    vc = g.vertex_color()
    sh_in = {"BaseCol": base, "PerInst": g.node("PerInstanceRandom"), "VCa": vc["A"], "VCb": vc["B"], "Nz": nz, "Season": mp["FoliageSeason"],
             "SeasonTint": mp["SeasonTint"], "Wet": mp["Wetness"], "Snow": mp["SnowAmount"], "VarA": var_a, "VarB": var_b, "TransCol": trans_col}
    for k in ("VarAmt", "VCAmt", "PatchAmt", "SeasonAmt", "AOStr", "TransAmt", "WetResp", "SnowResp", "RoughBase"):
        sh_in[k] = p[k]
    sh = g.custom(SOLID_SHADE, sh_in, out="float3", extra={"Sss": "float3", "Rough": "float", "AO": "float"}, desc="SolidFoliageShade")
    g.out(MP.MP_BASE_COLOR, sh)
    g.out(MP.MP_ROUGHNESS, sh["Rough"])
    g.out(MP.MP_AMBIENT_OCCLUSION, sh["AO"])
    g.out(MP.MP_SPECULAR, p["SpecBase"])
    g.out(MP.MP_METALLIC, p["Metal"])
    g.out(MP.MP_SUBSURFACE_COLOR, sh["Sss"])
    wind = _wind_node(g, vc["R"], vc["G"], uv0, p["UVMask"], p, mp)
    g.out(MP.MP_WORLD_POSITION_OFFSET, wind)
    return MM.finish(g, name)


# ------------------------------------------------------------------------------------------------------------------------------
def build_bark():
    name = "M_Roam_Bark"
    m = new_material(MAT_ROOT + "/" + name, used_with_nanite=True, used_with_instanced_static_meshes=True, max_world_position_offset_displacement=140.0)
    g = Graph(m)
    mpc_obj = load(MM.MPC_PATH)
    S, WX = "Surface", "Weather"
    paths = MM.pbr_texture_paths("tree_bark_a")
    p = {
        "NStr": g.scalar("NormalStrength", 1.0, S, 0, 3),
        "RoughScale": g.scalar("RoughnessScale", 1.0, S, 0, 2),
        "SpecBase": g.scalar("SpecularBase", 0.3, S, 0, 1),
        "VarAmt": g.scalar("VariationAmount", 0.5, S, 0, 1),
        "PatchAmt": g.scalar("PatchVariation", 0.3, S, 0, 1),
        "Sat": g.scalar("Saturation", 1.0, S, 0, 1.5),
        "AOStr": g.scalar("AOStrength", 1.0, S, 0, 1),
        "WetResp": g.scalar("WetnessResponse", 1.0, WX, 0, 1),
        "SnowResp": g.scalar("SnowResponse", 0.6, WX, 0, 1),
        "UScale": g.scalar("UVScaleU", 1.6, S, 0.1, 10),
        "VScale": g.scalar("UVScaleV", 1.6, S, 0.1, 10),
    }
    p.update(_wind_params(g, {"sway": 30.0, "flutter": 0.0}))
    p["UVMask"] = g.scalar("WindMaskFromUV", 0.0, "Wind", 0, 1)
    tint = g.vector("Tint", (1, 1, 1, 1), S)
    var_a = g.vector("VariationTintA", (0.85, 0.85, 0.85, 1), S)
    var_b = g.vector("VariationTintB", (1.15, 1.1, 1.05, 1), S)
    mp = MM.mpc_nodes(g, mpc_obj, ["WindDirection", "WindStrength", "WindSpeed", "Wetness", "SnowAmount"])
    uv0 = g.texcoord(0)
    wp = g.world_pos()
    nz = MM.noise_tex(g, wp["XY"] * (0.01 / 20.0))
    uv = g.custom("return TC0 * float2(UScale, VScale);", {"TC0": uv0, "UScale": p["UScale"], "VScale": p["VScale"]}, out="float2", desc="BarkUV")
    smp = MM.pbr_samples(g, uv, None, paths, S)
    vc = g.vertex_color()
    shade_in = {"BC": smp["bc_a"], "Nrm": smp["n_a"], "ORM": smp["orm_a"], "VCb": vc["B"], "VN": g.vertex_normal(), "PerInst": g.node("PerInstanceRandom"),
                "Nz": nz, "Wet": mp["Wetness"], "Snow": mp["SnowAmount"], "Tint": tint, "VarA": var_a, "VarB": var_b}
    for k in ("NStr", "RoughScale", "SpecBase", "VarAmt", "PatchAmt", "Sat", "AOStr", "WetResp", "SnowResp"):
        shade_in[k] = p[k]
    sh = g.custom(BARK_SHADE, shade_in, out="float3", extra={"Normal": "float3", "Rough": "float", "AO": "float", "Spec": "float"}, desc="BarkShade")
    g.out(MP.MP_BASE_COLOR, sh)
    g.out(MP.MP_NORMAL, sh["Normal"])
    g.out(MP.MP_ROUGHNESS, sh["Rough"])
    g.out(MP.MP_AMBIENT_OCCLUSION, sh["AO"])
    g.out(MP.MP_SPECULAR, sh["Spec"])
    wind = _wind_node(g, vc["R"], vc["G"], uv0, p["UVMask"], p, mp)
    g.out(MP.MP_WORLD_POSITION_OFFSET, wind)
    return MM.finish(g, name)


# ------------------------------------------------------------------------------------------------------------------------------
def build_rock():
    name = "M_Roam_Rock"
    m = new_material(MAT_ROOT + "/" + name, used_with_nanite=True, tangent_space_normal=False)
    g = Graph(m)
    mpc_obj = load(MM.MPC_PATH)
    S, WX, MS = "Surface", "Weather", "Moss"
    paths = MM.pbr_texture_paths("rock_grey")
    p = {
        "TileM": g.scalar("TileMetres", 4.0, S, 0.5, 20),
        "Sharp": g.scalar("BlendSharpness", 4.0, S, 1, 16),
        "RoughScale": g.scalar("RoughnessScale", 1.0, S, 0, 2),
        "AOStr": g.scalar("AOStrength", 1.0, S, 0, 1),
        "MacroAmt": g.scalar("MacroVariation", 0.5, S, 0, 1.5),
        "NStr": g.scalar("NormalStrength", 1.0, S, 0, 3),
        "SnowResp": g.scalar("SnowResponse", 1.0, WX, 0, 1),
        "WetResp": g.scalar("WetnessResponse", 1.0, WX, 0, 1),
        "MossAmount": g.scalar("MossAmount", 0.6, MS, 0, 1),
        "MossSlope": g.scalar("MossMinUpFacing", 0.55, MS, 0, 1),
        "MossHeightNoise": g.scalar("MossBreakup", 0.3, MS, 0, 1),
        "MossOn": g.scalar("MossEnabled", 1.0, MS, 0, 1),
    }
    tint = g.vector("Tint", (1, 1, 1, 1), S)
    moss_col = g.vector("MossColor", (0.04, 0.09, 0.02, 1), MS)
    snow_col = g.vector("SnowColor", (0.80, 0.83, 0.90, 1), WX)
    dust_col = g.vector("DustColor", (0.33, 0.26, 0.17, 1), WX)
    mp = MM.mpc_nodes(g, mpc_obj, ["Wetness", "SnowAmount", "DustAmount"])
    wp = g.world_pos()
    # planar projections (metres / tile): X-facing (y,-z), Y-facing (x,-z), Z-facing (x,y)
    pos = wp["XYZ"]
    uvs = g.custom("float3 q = WP * 0.01 / max(Tile, 0.01);\nUY = float2(q.x, -q.z);\nUZ = float2(q.x, q.y);\nreturn float2(q.y, -q.z);",
                   {"WP": pos, "Tile": p["TileM"]}, out="float2", extra={"UY": "float2", "UZ": "float2"}, desc="Triplanar UV")
    sx = MM.pbr_samples(g, uvs, None, paths, S)
    sy = MM.pbr_samples(g, uvs["UY"], None, paths, S)
    sz = MM.pbr_samples(g, uvs["UZ"], None, paths, S)
    nz = MM.noise_tex(g, wp["XY"] * (0.01 / 16.0))
    shade_in = {
        "WPos": pos, "VN": g.vertex_normal(), "Sharp": p["Sharp"],
        "BCx": sx["bc_a"], "BCy": sy["bc_a"], "BCz": sz["bc_a"], "ORMx": sx["orm_a"], "ORMy": sy["orm_a"], "ORMz": sz["orm_a"],
        "Nx": sx["n_a"], "Ny": sy["n_a"], "Nz": sz["n_a"], "NStr": p["NStr"],
        "Tint": tint, "RoughScale": p["RoughScale"], "AOStr": p["AOStr"], "MacroAmt": p["MacroAmt"], "Noi": nz,
        "MossSlope": p["MossSlope"], "MossAmount": p["MossAmount"], "MossHeightNoise": p["MossHeightNoise"], "MossOn": p["MossOn"],
        "MossCol": moss_col, "SnowCol": snow_col, "DustCol": dust_col, "Snow": mp["SnowAmount"], "SnowResp": p["SnowResp"],
        "Wet": mp["Wetness"], "WetResp": p["WetResp"], "Dust": mp["DustAmount"],
    }
    sh = g.custom(ROCK_SHADE, shade_in, out="float3", extra={"Rough": "float", "AO": "float", "NormalWS": "float3"}, desc="RockShade")
    g.out(MP.MP_BASE_COLOR, sh)
    g.out(MP.MP_NORMAL, sh["NormalWS"])
    g.out(MP.MP_ROUGHNESS, sh["Rough"])
    g.out(MP.MP_AMBIENT_OCCLUSION, sh["AO"])
    return MM.finish(g, name)


# ------------------------------------------------------------------------------------------------------------------------------
def build_tree_far():
    """Two crossed distance cards (Exports/Nature/Trees/<id>_Far.fbx): baked colour + alpha atlas, masked, two-sided."""
    name = "M_Roam_Tree_Far"
    m = new_material(MAT_ROOT + "/" + name, blend_mode=unreal.BlendMode.BLEND_MASKED, two_sided=True, opacity_mask_clip_value=0.33,
                     used_with_instanced_static_meshes=True)
    g = Graph(m)
    mpc_obj = load(MM.MPC_PATH)
    uv0 = g.texcoord(0)
    tex = g.texture("CardTex", T.tex_path("farcard_tree_oak_a", "BC"), "color", uv0, "Card")
    tint = g.vector("Tint", (1, 1, 1, 1), "Card")
    rough = g.scalar("Roughness", 0.8, "Card", 0, 1)
    spec = g.scalar("Specular", 0.1, "Card", 0, 1)
    mp = MM.mpc_nodes(g, mpc_obj, ["Wetness"])
    col = tex["RGB"] * tint * g.lerp(1.0, 0.8, mp["Wetness"])
    g.out(MP.MP_BASE_COLOR, col)
    g.out(MP.MP_OPACITY_MASK, tex["A"])
    g.out(MP.MP_ROUGHNESS, rough)
    g.out(MP.MP_SPECULAR, spec)
    return MM.finish(g, name)


BUILDERS = {
    "M_Roam_Foliage_Masked": build_foliage,
    "M_Roam_Foliage_Solid": build_foliage_solid,
    "M_Roam_Bark": build_bark,
    "M_Roam_Grass_Blade": build_grass,
    "M_Roam_Flower": build_flower,
    "M_Roam_Rock": build_rock,
    "M_Roam_Tree_Far": build_tree_far,
}
