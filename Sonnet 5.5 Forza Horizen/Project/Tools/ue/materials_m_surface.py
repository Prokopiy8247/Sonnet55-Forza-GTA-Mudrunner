"""Surface masters: buildings / structures / roadside kit.

  M_Roam_Building        generic textured solid (plaster, brick, stone, wood, metal sheets, roof tiles, concrete, bridge / tunnel / curb / roadside
                         concrete ...).  Mapping: UV0 (metric, TileMetres per texture tile), UV1 (road-chunk metric), or world-aligned triplanar.
  M_Roam_Glass_Building  translucent window glass with a procedural window grid that lights up at night (MPC TimeOfDay / NightFactor).
  M_Roam_Roadside        flat-colour paint / plastic / rubber / metal / sign faces / reflectors / lamp lens (no textures, noise breakup,
                         retro-reflective night boost, optional emission).
  M_Roam_Billboard       billboard face (ad texture, UV 0..1) with a night glow.
Parameter names: Docs/Tech/MATERIALS.md.
"""
import os
import sys

import unreal

_HERE = os.path.dirname(os.path.abspath(globals().get("__file__", unreal.Paths.project_dir() + "Tools/ue/materials_m_surface.py")))
if _HERE not in sys.path:
    sys.path.insert(0, _HERE)
import materials_lib as L  # noqa: E402
from materials_lib import Graph, MAT_ROOT, MP, load, new_material  # noqa: E402
import materials_masters as MM  # noqa: E402
import materials_textures as T  # noqa: E402

# ------------------------------------------------------------------------------------------------------------------------------
# M_Roam_Building
# ------------------------------------------------------------------------------------------------------------------------------
BLD_UV = """
float2 uv = TC / max(Tile, 0.01);
if (Swap > 0.5) uv = uv.yx;
return uv;
"""

TRI_UV = """
float3 q = WP * 0.01 / max(Tile, 0.01);
float2 ux = float2(q.y, -q.z);
UY = float2(q.x, -q.z);
UZ = float2(q.x, q.y);
if (Swap > 0.5) { ux = ux.yx; UY = UY.yx; UZ = UZ.yx; }
return ux;
"""

TRI_BLEND = """
float3 an = pow(abs(VN), Sharp);
an /= max(an.x + an.y + an.z, 1e-4);
float3 sg = float3((VN.x >= 0.0) ? 1.0 : -1.0, (VN.y >= 0.0) ? 1.0 : -1.0, (VN.z >= 0.0) ? 1.0 : -1.0);
float3 tx = float3(Nx.xy, max(Nx.z, 0.2));
float3 ty = float3(Ny.xy, max(Ny.z, 0.2));
float3 tz = float3(Nz.xy, max(Nz.z, 0.2));
float3 nX = float3(sg.x * tx.z, tx.x, -tx.y);
float3 nY = float3(ty.x, sg.y * ty.z, -ty.y);
float3 nZ = float3(tz.x, tz.y, sg.z * tz.z);
NW = normalize(nX * an.x + nY * an.y + nZ * an.z + 1e-5);
ORM = ORMx * an.x + ORMy * an.y + ORMz * an.z;
return BCx * an.x + BCy * an.y + BCz * an.z;
"""

NOISE_UV = """
return float2((WP.x + WP.y) * 0.7071, WP.z) * (0.01 / 12.0);
"""

BLD_SHADE = """
float3 vc = lerp(float3(1.0, 1.0, 1.0), VC.rgb, VCT);
float3 col = BC * Tint.rgb * vc;
float macroN = (Noi.r - 0.5) + (Noi.g - 0.5) * 0.5;
col *= 1.0 + macroN * MacroAmt;
float rough = saturate(ORM.g * RoughScale + RoughBias + (Noi.b - 0.5) * 0.15 * MacroAmt);
float metal = saturate(ORM.b * MetalScale + MetalBias);
float ao = lerp(1.0, ORM.r, AOStr);
float up = VN.z;
float2 nxy = NTS.xy * NStr;

float wet = saturate(Wet * WetResp);
col *= lerp(1.0, 0.68, wet * (1.0 - metal));
rough = lerp(rough, rough * 0.5, wet);

float snowM = saturate(Snow * SnowResp * 1.6) * smoothstep(0.30 - Snow * 0.25, 0.80, up + (Noi.g - 0.5) * 0.4);
col = lerp(col, SnowCol.rgb, snowM);
rough = lerp(rough, 0.7, snowM);
metal *= 1.0 - snowM;
nxy *= 1.0 - 0.5 * snowM;

float dustM = saturate(Dust * DustResp * (0.35 + Noi.b)) * (1.0 - snowM) * (1.0 - wet) * (0.4 + 0.6 * saturate(up));
col = lerp(col, DustCol.rgb * (0.6 + col.g), dustM * 0.45);
rough = lerp(rough, 0.9, dustM * 0.5);

Normal = normalize(float3(nxy, max(NTS.z, 0.2)));
Rough = saturate(rough);
Metal = metal;
AO = ao;
return col;
"""


def build_building():
    name = "M_Roam_Building"
    m = new_material(MAT_ROOT + "/" + name, used_with_nanite=True)
    g = Graph(m)
    mpc = load(MM.MPC_PATH)
    S, WX = "Surface", "Weather"
    paths = MM.pbr_texture_paths("plaster_white")

    tile = g.scalar("TileMetres", 2.0, S, 0.1, 20)
    swap = g.scalar("SwapUV", 0.0, S, 0, 1)
    tint = g.vector("BaseTint", (1, 1, 1, 1), S)
    vct = g.scalar("VertexColorTint", 1.0, S, 0, 1)
    nstr = g.scalar("NormalStrength", 1.0, S, 0, 3)
    rscale = g.scalar("RoughnessScale", 1.0, S, 0, 2)
    rbias = g.scalar("RoughnessBias", 0.0, S, -0.5, 0.5)
    mscale = g.scalar("MetallicScale", 1.0, S, 0, 1)
    mbias = g.scalar("MetallicBias", 0.0, S, 0, 1)
    aostr = g.scalar("AOStrength", 1.0, S, 0, 1)
    macro = g.scalar("MacroVariation", 0.6, S, 0, 2)
    spec_base = g.scalar("SpecularBase", 0.5, S, 0, 1)
    sharp = g.scalar("BlendSharpness", 4.0, S, 1, 16)
    wet_r = g.scalar("WetnessResponse", 1.0, WX, 0, 1)
    snow_r = g.scalar("SnowResponse", 0.6, WX, 0, 1)
    dust_r = g.scalar("DustResponse", 0.6, WX, 0, 1)
    snow_c = g.vector("SnowColor", (0.80, 0.83, 0.90, 1), WX)
    dust_c = g.vector("DustColor", (0.33, 0.26, 0.17, 1), WX)

    mp = MM.mpc_nodes(g, mpc, ["Wetness", "SnowAmount", "DustAmount"])
    wp = g.world_pos()["XYZ"]
    vn = g.vertex_normal()
    vcol = g.vertex_color()

    # ---- mapping A: UV0 or UV1 (static switch UseUV1: road chunks carry metric coordinates in UV1)
    tc = g.switch("UseUV1", False, g.texcoord(1), g.texcoord(0), S)
    uvq = g.custom(BLD_UV, {"TC": tc, "Tile": tile, "Swap": swap}, out="float2", desc="BuildingUV")
    s_uv = MM.pbr_samples(g, uvq, None, paths, S)

    # ---- mapping B: world-aligned triplanar (static switch Triplanar)
    uvt = g.custom(TRI_UV, {"WP": wp, "Tile": tile, "Swap": swap}, out="float2", extra={"UY": "float2", "UZ": "float2"}, desc="TriUV")
    sx = MM.pbr_samples(g, uvt, None, paths, S)
    sy = MM.pbr_samples(g, uvt["UY"], None, paths, S)
    sz = MM.pbr_samples(g, uvt["UZ"], None, paths, S)
    tri = g.custom(TRI_BLEND, {"VN": vn, "Sharp": sharp, "BCx": sx["bc_a"], "BCy": sy["bc_a"], "BCz": sz["bc_a"],
                               "ORMx": sx["orm_a"], "ORMy": sy["orm_a"], "ORMz": sz["orm_a"],
                               "Nx": sx["n_a"], "Ny": sy["n_a"], "Nz": sz["n_a"]},
                   out="float3", extra={"ORM": "float3", "NW": "float3"}, desc="TriBlend")
    nts_tri = g.node("Transform", {"transform_source_type": unreal.MaterialVectorCoordTransformSource.TRANSFORMSOURCE_WORLD,
                                   "transform_type": unreal.MaterialVectorCoordTransform.TRANSFORM_TANGENT}, {"Input": tri["NW"]})
    bc = g.switch("Triplanar", False, tri, s_uv["bc_a"], S)
    orm = g.switch("Triplanar", False, tri["ORM"], s_uv["orm_a"], S)
    nts = g.switch("Triplanar", False, nts_tri, s_uv["n_a"], S)

    noi_uv = g.custom(NOISE_UV, {"WP": wp}, out="float2", desc="NoiseUV")
    noi = MM.noise_tex(g, noi_uv)
    shade = g.custom(BLD_SHADE, {
        "BC": bc, "ORM": orm, "NTS": nts, "VN": vn, "VC": vcol, "Noi": noi,
        "Tint": tint, "VCT": vct, "NStr": nstr, "RoughScale": rscale, "RoughBias": rbias, "MetalScale": mscale, "MetalBias": mbias,
        "AOStr": aostr, "MacroAmt": macro,
        "Wet": mp["Wetness"], "Snow": mp["SnowAmount"], "Dust": mp["DustAmount"], "WetResp": wet_r, "SnowResp": snow_r, "DustResp": dust_r,
        "SnowCol": snow_c, "DustCol": dust_c,
    }, out="float3", extra={"Normal": "float3", "Rough": "float", "Metal": "float", "AO": "float"}, desc="BuildingShade")
    g.out(MP.MP_BASE_COLOR, shade)
    g.out(MP.MP_NORMAL, shade["Normal"])
    g.out(MP.MP_ROUGHNESS, shade["Rough"])
    g.out(MP.MP_METALLIC, shade["Metal"])
    g.out(MP.MP_AMBIENT_OCCLUSION, shade["AO"])
    g.out(MP.MP_SPECULAR, spec_base)
    return MM.finish(g, name)


# ------------------------------------------------------------------------------------------------------------------------------
# M_Roam_Glass_Building
# ------------------------------------------------------------------------------------------------------------------------------
GLASS_SHADE = MM.NIGHT_HLSL + """
// ---- window grid (metres): per-window random lit state, per-object offset so neighbouring buildings differ
float2 cellSz = float2(max(WinW, 0.2), max(WinH, 0.2));
float2 g2 = TC / cellSz;
float2 cell = floor(g2);
float2 cf = frac(g2);
float seed = frac(dot(OPos.xy, float2(0.0123, 0.0311)) + OPos.z * 0.0071);
float h1 = frac(sin(dot(cell + seed * 57.0, float2(127.1, 311.7))) * 43758.5453);
float h2 = frac(sin(dot(cell + seed * 57.0, float2(269.5, 183.3))) * 43758.5453);
float h3 = frac(sin(dot(cell + seed * 57.0, float2(419.2, 371.9))) * 43758.5453);
// window pane (inset), frame is dark
float2 ed = min(cf, 1.0 - cf) * cellSz;
float pane = saturate(min(ed.x, ed.y) / max(FrameW, 1e-3) - 0.5);
float lit = step(h1, LitFrac) * pane * nightF * WinLit;
float3 warm = lerp(LitColA.rgb, LitColB.rgb, step(h2, 0.5));
float tv = step(0.9, h3);
warm = lerp(warm, float3(0.45, 0.6, 1.0), tv * 0.6);
float flick = lerp(1.0, 0.75 + 0.25 * sin(Tsec * 9.0 + h2 * 40.0), tv);
// curtains / blinds: some lit windows are dimmer
float dim = lerp(0.35, 1.0, frac(h2 * 7.31));
Emis = warm * LitInt * lit * dim * flick;
// ---- glass look
float ndv = saturate(dot(normalize(VN), normalize(CamV)));
float fres = pow(1.0 - ndv, FresnelExp);
float dirtA = Dirt.a * DirtAmt;
float3 col = lerp(GlassCol.rgb, Dirt.rgb, saturate(dirtA));
float opac = lerp(OpFacing, OpGrazing, fres) + dirtA * 0.5;
opac = lerp(opac, 0.95, lit);
// frame
col = lerp(col, FrameCol.rgb, (1.0 - pane) * WinLit);
opac = lerp(opac, 1.0, (1.0 - pane) * WinLit);
Opac = saturate(opac);
Rough = saturate(lerp(GlassRough, 0.55, saturate(dirtA * 1.5)));
return col;
"""


def build_glass():
    name = "M_Roam_Glass_Building"
    m = new_material(MAT_ROOT + "/" + name, blend_mode=unreal.BlendMode.BLEND_TRANSLUCENT, two_sided=True)
    m.set_editor_property("translucency_lighting_mode", unreal.TranslucencyLightingMode.TLM_SURFACE_PER_PIXEL_LIGHTING)
    g = Graph(m)
    mpc = load(MM.MPC_PATH)
    S, N, D = "Glass", "Night windows", "Dirt"
    tc = g.texcoord(0)
    p = {
        "WinW": g.scalar("WindowWidth", 1.6, N, 0.3, 6),
        "WinH": g.scalar("WindowHeight", 1.5, N, 0.3, 6),
        "FrameW": g.scalar("FrameWidth", 0.07, N, 0.01, 0.4),
        "WinLit": g.scalar("WindowGridEnabled", 1.0, N, 0, 1),
        "LitFrac": g.scalar("LitFraction", 0.35, N, 0, 1),
        "LitInt": g.scalar("LitIntensity", 5.0, N, 0, 200),
        "FresnelExp": g.scalar("FresnelExponent", 3.5, S, 1, 8),
        "OpFacing": g.scalar("OpacityFacing", 0.22, S, 0, 1),
        "OpGrazing": g.scalar("OpacityGrazing", 0.85, S, 0, 1),
        "GlassRough": g.scalar("GlassRoughness", 0.04, S, 0, 1),
        "DirtAmt": g.scalar("DirtAmount", 0.5, D, 0, 1),
        "DirtTile": g.scalar("DirtTileMetres", 1.5, D, 0.2, 10),
    }
    glass_col = g.vector("GlassColor", (0.12, 0.2, 0.22, 1), S)
    frame_col = g.vector("FrameColor", (0.05, 0.05, 0.055, 1), N)
    lit_a = g.vector("LitColorWarm", (1.0, 0.72, 0.38, 1), N)
    lit_b = g.vector("LitColorCool", (1.0, 0.92, 0.75, 1), N)
    spec = g.scalar("SpecularBase", 0.9, S, 0, 1)
    mp = MM.mpc_nodes(g, mpc, ["TimeOfDay", "NightFactor"])
    dirt_tex = T.tex_path("glass_dirt_overlay", "BC")
    wp = g.world_pos()["XYZ"]
    dirt_uv = g.custom("return TC / max(Tile, 0.1);", {"TC": tc, "Tile": p["DirtTile"]}, out="float2", desc="DirtUV")
    dirt = g.texture("DirtTex", dirt_tex, "color", dirt_uv, D)["RGBA"]
    opos = g.node("ObjectPositionWS")
    vn = g.vertex_normal()
    camv = g.camera_vector()
    tsec = g.time()
    shade = g.custom(GLASS_SHADE, {
        "TC": tc, "OPos": opos, "VN": vn, "CamV": camv, "Tsec": tsec, "Hour": mp["TimeOfDay"], "NightOv": mp["NightFactor"], "Dirt": dirt,
        "GlassCol": glass_col, "FrameCol": frame_col, "LitColA": lit_a, "LitColB": lit_b,
        "WinW": p["WinW"], "WinH": p["WinH"], "FrameW": p["FrameW"], "WinLit": p["WinLit"], "LitFrac": p["LitFrac"], "LitInt": p["LitInt"],
        "FresnelExp": p["FresnelExp"], "OpFacing": p["OpFacing"], "OpGrazing": p["OpGrazing"], "GlassRough": p["GlassRough"], "DirtAmt": p["DirtAmt"],
    }, out="float3", extra={"Emis": "float3", "Opac": "float", "Rough": "float"}, desc="GlassShade")
    g.out(MP.MP_BASE_COLOR, shade)
    g.out(MP.MP_EMISSIVE_COLOR, shade["Emis"])
    g.out(MP.MP_OPACITY, shade["Opac"])
    g.out(MP.MP_ROUGHNESS, shade["Rough"])
    g.out(MP.MP_SPECULAR, spec)
    g.out(MP.MP_METALLIC, 0.0)
    return MM.finish(g, name)


# ------------------------------------------------------------------------------------------------------------------------------
# M_Roam_Roadside (flat colour materials)
# ------------------------------------------------------------------------------------------------------------------------------
RS_SHADE = MM.NIGHT_HLSL + """
float3 vc = lerp(float3(1.0, 1.0, 1.0), VC.rgb, VCT);
float breakup = (Noi.r - 0.5) + (Noi.g - 0.5) * 0.6;
float3 col = Col.rgb * vc * (1.0 + breakup * Breakup);
float rough = saturate(RoughV + (Noi.b - 0.5) * RoughBreakup);
float metal = Metal;
float wet = saturate(Wet * WetResp);
col *= lerp(1.0, 0.75, wet * (1.0 - metal));
rough = lerp(rough, rough * 0.6, wet);
float snowM = saturate(Snow * SnowResp * 1.6) * smoothstep(0.30, 0.80, VN.z + (Noi.g - 0.5) * 0.4);
col = lerp(col, float3(0.8, 0.83, 0.9), snowM);
rough = lerp(rough, 0.7, snowM);
metal *= 1.0 - snowM;
float dustM = saturate(Dust * 0.6 * (0.35 + Noi.b)) * (1.0 - snowM) * (1.0 - wet);
col = lerp(col, float3(0.33, 0.26, 0.17) * (0.6 + col.g), dustM * 0.4);
// emission: 0 none, 1 always, 2 night only
float eMask = (EmitMode > 1.5) ? nightF : ((EmitMode > 0.5) ? 1.0 : 0.0);
float3 emis = EmCol.rgb * EmInt * eMask;
// retro-reflective response: bright when seen from near the (headlight) beam axis at night, falls off with distance
float3 V = normalize(CamP - WPos);
float ndv = saturate(dot(normalize(VN), V));
float dist = distance(CamP, WPos) * 0.01;
float fall = saturate(1.0 - dist / max(RetroRange, 1.0));
float retro = Retro * Head * nightF * pow(ndv, 3.0) * fall * fall;
emis += col * retro * 0.8;
Emis = emis;
Rough = rough;
MetalO = metal;
return col;
"""


def build_roadside():
    name = "M_Roam_Roadside"
    m = new_material(MAT_ROOT + "/" + name, used_with_nanite=True)
    g = Graph(m)
    mpc = load(MM.MPC_PATH)
    S, WX, EM = "Surface", "Weather", "Emission"
    col = g.vector("BaseColor", (0.5, 0.5, 0.5, 1), S)
    p = {
        "Metal": g.scalar("Metallic", 0.0, S, 0, 1),
        "RoughV": g.scalar("Roughness", 0.5, S, 0, 1),
        "VCT": g.scalar("VertexColorTint", 1.0, S, 0, 1),
        "Breakup": g.scalar("ColorBreakup", 0.12, S, 0, 1),
        "RoughBreakup": g.scalar("RoughnessBreakup", 0.2, S, 0, 1),
        "Retro": g.scalar("RetroReflective", 0.0, EM, 0, 6),
        "RetroRange": g.scalar("RetroRangeMetres", 90.0, EM, 5, 400),
        "EmitMode": g.scalar("EmissionMode", 0.0, EM, 0, 2),  # 0 off, 1 always, 2 night only
        "EmInt": g.scalar("EmissiveIntensity", 0.0, EM, 0, 100),
        "WetResp": g.scalar("WetnessResponse", 1.0, WX, 0, 1),
        "SnowResp": g.scalar("SnowResponse", 0.5, WX, 0, 1),
    }
    spec = g.scalar("SpecularBase", 0.5, S, 0, 1)
    em_col = g.vector("EmissiveColor", (1.0, 0.85, 0.6, 1), EM)
    mp = MM.mpc_nodes(g, mpc, ["Wetness", "SnowAmount", "DustAmount", "TimeOfDay", "NightFactor", "Headlights"])
    wp = g.world_pos()["XYZ"]
    noi_uv = g.custom(NOISE_UV, {"WP": wp}, out="float2", desc="NoiseUV")
    noi = MM.noise_tex(g, noi_uv)
    shade = g.custom(RS_SHADE, {
        "Col": col, "VC": g.vertex_color(), "VN": g.vertex_normal(), "WPos": wp, "CamP": g.camera_pos(), "Noi": noi,
        "Hour": mp["TimeOfDay"], "NightOv": mp["NightFactor"], "Wet": mp["Wetness"], "Snow": mp["SnowAmount"], "Dust": mp["DustAmount"], "Head": mp["Headlights"],
        "EmCol": em_col, **p,
    }, out="float3", extra={"Emis": "float3", "Rough": "float", "MetalO": "float"}, desc="RoadsideShade")
    g.out(MP.MP_BASE_COLOR, shade)
    g.out(MP.MP_EMISSIVE_COLOR, shade["Emis"])
    g.out(MP.MP_ROUGHNESS, shade["Rough"])
    g.out(MP.MP_METALLIC, shade["MetalO"])
    g.out(MP.MP_SPECULAR, spec)
    return MM.finish(g, name)


# ------------------------------------------------------------------------------------------------------------------------------
# M_Roam_Billboard
# ------------------------------------------------------------------------------------------------------------------------------
def build_billboard():
    name = "M_Roam_Billboard"
    m = new_material(MAT_ROOT + "/" + name, used_with_nanite=True)
    g = Graph(m)
    mpc = load(MM.MPC_PATH)
    S = "Billboard"
    tc = g.texcoord(0)
    tex = g.texture("AdTex", "%s/Roadside/T_RS_BillboardAd_A" % L.TEX_ROOT, "color", tc, S)
    glow = g.scalar("NightGlow", 0.35, S, 0, 3)
    rough = g.scalar("Roughness", 0.55, S, 0, 1)
    spec = g.scalar("SpecularBase", 0.35, S, 0, 1)
    mp = MM.mpc_nodes(g, mpc, ["TimeOfDay", "NightFactor"])
    night = g.custom(MM.NIGHT_HLSL + "return nightF;", {"Hour": mp["TimeOfDay"], "NightOv": mp["NightFactor"]}, out="float", desc="Night")
    g.out(MP.MP_BASE_COLOR, tex["RGB"])
    g.out(MP.MP_EMISSIVE_COLOR, tex["RGB"] * (night * glow))
    g.out(MP.MP_ROUGHNESS, rough)
    g.out(MP.MP_SPECULAR, spec)
    return MM.finish(g, name)


BUILDERS = {
    "M_Roam_Building": build_building,
    "M_Roam_Glass_Building": build_glass,
    "M_Roam_Roadside": build_roadside,
    "M_Roam_Billboard": build_billboard,
}
