"""M_Roam_Road - the road master (asphalt / concrete / dirt / gravel variants are instances with different textures + parameters).

Mesh contract (road chunks, Exports/Roads/chunks.json, written by Tools/blender/world/roadgeo.py):
    UV1 = (d, s)            lateral metres from the CENTRE LINE (right = +) and arc length in metres  -> metric texture tiling + all paint
    UV2 = (P, lw)           paved (carriageway) half width and lane width in metres; P = 0 on junction pads = NO markings
    UV3 = (median, zone)    median width in metres; zone 1.0 carriageway / 0.66 shoulder / 0.5 curb / 0.33 barrier / 0 skirt
Everything (texture tiling, lane markings, wheel tracks, ripples, shoulder blend) is driven from UV1..UV3, so it is metric and independent of
the road width.  Paint: edge lines at |d| = P - EdgeLineInset, lane dividers (dashed) at |d| = median/2 + k*lw, centre line (dashed / solid /
double) when there is no median.
"""
import os
import sys

import unreal

_HERE = os.path.dirname(os.path.abspath(globals().get("__file__", unreal.Paths.project_dir() + "Tools/ue/materials_m_road.py")))
if _HERE not in sys.path:
    sys.path.insert(0, _HERE)
import materials_lib as L  # noqa: E402
from materials_lib import Graph, MAT_ROOT, MP, load, new_material  # noqa: E402
import materials_masters as MM  # noqa: E402
import materials_textures as T  # noqa: E402

UV_GEN = """
float2 uv = TC1 / max(Tile, 0.01);
// AcrossMode 1: the texture spans the paved width (dirt road with ruts), mirrored outside it
float P2 = max(2.0 * TC2.x, 1.0);
float tx = TC1.x / P2 + 0.5;
float2 uvA = float2(1.0 - abs(frac(tx * 0.5) * 2.0 - 1.0), TC1.y / P2);
uv = lerp(uv, uvA, Across);
float2 uvR = float2(0.8660254 * uv.x - 0.5 * uv.y, 0.5 * uv.x + 0.8660254 * uv.y);
UVB = uvR * 0.7311 + float2(0.37, 0.61);
Wt = smoothstep(0.40, 0.60, NzA.r) * AntiAmt;
return uv;
"""

SHADE = """
float3 bc = lerp(BCa, BCb, Wt);
float3 nrm = lerp(Na, Nb, Wt);
float3 orm = lerp(ORMa, ORMb, Wt);

// ---- road frame from the mesh UVs
// UE flips V when it imports an FBX: UV channels arrive as (u, 1 - v), so the V-carried values (arc length s, lane width, zone) are un-flipped here
// (UVFlipV = 1; set 0 for meshes that did not go through the FBX importer)
float vfl = UVFlipV;
float d = TC1.x;
float s = lerp(TC1.y, 1.0 - TC1.y, vfl);
float ad = abs(d);
float P = TC2.x;
float lwIn = lerp(TC2.y, 1.0 - TC2.y, vfl);
float lw = (lwIn > 0.5) ? lwIn : FallLaneW;
float med = TC3.x;
float medH = med * 0.5;
float zone = lerp(TC3.y, 1.0 - TC3.y, vfl);
float aaX = max(fwidth(d), 1e-3);
float aaY = max(fwidth(s), 1e-3);
float hasP = (P > 0.5) ? 1.0 : 0.0;
float inCar = smoothstep(0.90, 0.99, zone) * hasP * saturate((P - ad) / aaX + 0.5);

// ---- shoulder: secondary (plain, metric) texture set + tint, fades in from the carriageway edge to the shoulder outer edge
float shAmt = saturate((1.0 - zone) / 0.34);
float shW = smoothstep(0.05, 0.55, shAmt) * ShSetMix;
bc = lerp(bc, BCs, shW);
nrm = lerp(nrm, Ns, shW);
orm = lerp(orm, ORMs, shW);

// ---- base surface + macro variation (hides tiling)
float macroN = NzA.r - 0.5;
float3 base = bc * Tint.rgb * (1.0 + macroN * 0.55 * MacroAmt);
base = lerp(base, base * ShTint.rgb, saturate(shAmt * 1.5) * ShTintAmt);
float rough = saturate(orm.g * RoughScale + RoughBias + (NzA.g - 0.5) * 0.20 * MacroAmt);
float ao = lerp(1.0, orm.r, AOStr);
float2 nxy = nrm.xy * NormStr;
float spec = SpecBase;

// ---- polished / oily wheel paths in every lane
float lx = (frac(max(ad - medH, 0.0) / lw) - 0.5) * lw;
float tq = (abs(lx) - TrackSpacing * 0.5) / 0.30;
float tr = exp(-tq * tq) * inCar * TrackDark;
tr *= 0.65 + 0.7 * NzB.g;
base *= 1.0 - 0.45 * tr;
rough -= 0.07 * tr;

// ---- wetness / puddles
float damp = saturate(Wet * WetResp);
float pud = max(Puddle, damp * damp * 0.5) * PuddleResp;
float lowSp = NzA.r * 0.55 + NzB.r * 0.45;
float thr = 0.86 - pud * 0.55;
float pm = smoothstep(thr, thr + 0.05, lowSp) * saturate(pud * 8.0);
base *= lerp(1.0, 0.62, damp);
rough = lerp(rough, max(0.12, rough * 0.38), damp);

// ---- lane markings (paint)
#define RLD(c, hw) saturate(((hw) - abs(ad - (c))) / aaX + 0.5)
float cover = 0.0;
float coverC = 0.0;
float Pd = max(DashLen + DashGap, 0.1);
float sy = frac((s + DashPhase) / Pd) * Pd;
float dd = min(abs(sy - DashLen * 0.5), abs(sy - Pd - DashLen * 0.5));
float dash = saturate((DashLen * 0.5 - dd) / aaY + 0.5);
float ew = EdgeW * 0.5;
cover = max(cover, RLD(P - EdgeInset - ew, ew));
// lane dividers (between the lanes of one direction)
int nDir = (int)floor((P - medH - EdgeInset) / lw + 0.5);
[unroll]
for (int k = 1; k < 5; k++)
{
    float act = (k < nDir) ? 1.0 : 0.0;
    cover = max(cover, RLD(medH + k * lw, LaneLineW * 0.5) * dash * act);
}
// centre line (only when there is no median)
float cw2 = CentreW * 0.5;
float dg = DblGap * 0.5 + cw2;
float cLine = RLD(0.0, cw2);
float cDbl = RLD(dg, cw2);
float cm = (CentreStyle < 0.5) ? cLine * dash : ((CentreStyle < 1.5) ? cLine : ((CentreStyle < 2.5) ? cDbl : 0.0));
coverC = cm * ((med < 0.1) ? 1.0 : 0.0);
float wearN = saturate(NzC.g * 0.7 + NzC.b * 0.5);
float wearMask = saturate(1.0 - Wear * smoothstep(0.30, 0.75, wearN) * 1.4);
float mk = MarkOn * wearMask * inCar;
cover *= mk;
coverC *= mk;
float wetPaint = lerp(1.0, 0.78, damp);
base = lerp(base, MarkCol.rgb * wetPaint, cover);
base = lerp(base, CentreCol.rgb * wetPaint, coverC);
float cv = max(cover, coverC);
rough = lerp(rough, lerp(MarkRough, MarkRough * 0.55, damp), cv);
nxy *= 1.0 - 0.35 * cv;

// ---- puddles on top of everything (paint stays visible under the water film)
base = lerp(base, base * 0.6, pm);
rough = lerp(rough, 0.03, pm);
nxy = lerp(nxy, float2(0.0, 0.0), pm * 0.95);
spec = lerp(spec, 0.5, saturate(damp * 0.5 + pm));

// ---- rain ripples (tangent space: UV1 = metres across / along)
float rainOn = saturate(Rain * 2.0) * saturate(damp * 1.5 + pm);
if (rainOn > 0.01 && RippleStr > 0.0)
{
    float2 rip = float2(0.0, 0.0);
    [unroll]
    for (int i = 0; i < 2; i++)
    {
        float2 q = TC1 * ((i == 0) ? 2.6 : 4.3) + float(i) * 17.31;
        float2 cell = floor(q);
        float2 f = frac(q) - 0.5;
        float h1 = frac(sin(dot(cell, float2(127.1, 311.7))) * 43758.5453);
        float h2 = frac(sin(dot(cell, float2(269.5, 183.3))) * 43758.5453);
        float2 dv = f - (float2(h1, h2) - 0.5) * 0.5;
        float dl = length(dv) + 1e-4;
        float life = frac(Tsec * (0.8 + 0.5 * h1) + h2);
        float xx = dl - life * 0.42;
        float env = exp(-xx * xx * 220.0) * (1.0 - life) * (1.0 - life);
        float dh = (cos(xx * 55.0) * 55.0 - 440.0 * xx * sin(xx * 55.0)) * env;
        rip -= (dv / dl) * dh * 0.0055;
    }
    nxy += rip * rainOn * RippleStr;
}

// ---- snow (lanes stay clear, shoulders whiten)
float snowCov = saturate((Snow * SnowResp * 1.5 - 0.05 - NzA.r * 0.45) * 5.0);
snowCov *= lerp(1.0, 1.0 - SnowClear, inCar);
base = lerp(base, SnowCol.rgb, snowCov);
rough = lerp(rough, 0.72, snowCov);
nxy *= lerp(1.0, 0.45, snowCov);
spec = lerp(spec, 0.5, snowCov);

// ---- dust
float dustCov = saturate(Dust * DustResp * (0.35 + 1.1 * NzB.g)) * (1.0 - snowCov) * (1.0 - pm) * (1.0 - damp);
base = lerp(base, DustCol.rgb * (0.6 + 0.8 * bc.g), dustCov * 0.5);
rough = lerp(rough, 0.92, dustCov);

Normal = normalize(float3(nxy, max(nrm.z, 0.2)));
Rough = saturate(rough);
AO = ao;
Spec = spec;
return base;
"""


def build_road():
    name = "M_Roam_Road"
    m = new_material(MAT_ROOT + "/" + name, used_with_nanite=True)
    g = Graph(m)
    mpc = load(MM.MPC_PATH)
    pbr = MM.pbr_texture_paths("asphalt_new")
    pbr_sh = MM.pbr_texture_paths("dirt_road")
    noise_path = T.tex_path("tileable_perlin_noise", "D")

    uv1 = g.texcoord(1)
    uv2 = g.texcoord(2)
    uv3 = g.texcoord(3)
    S, MK, WX = "Surface", "Markings", "Weather"

    # ---- parameters
    tile = g.scalar("TileMetres", 3.0, S, 0.2, 20)
    across = g.scalar("AcrossMode", 0.0, S, 0, 1)
    anti_amt = g.scalar("AntiTileAmount", 1.0, S, 0, 1)
    tint = g.vector("BaseTint", (1, 1, 1, 1), S)
    nstr = g.scalar("NormalStrength", 1.0, S, 0, 3)
    rscale = g.scalar("RoughnessScale", 1.0, S, 0, 2)
    rbias = g.scalar("RoughnessBias", 0.0, S, -0.5, 0.5)
    aostr = g.scalar("AOStrength", 1.0, S, 0, 1)
    macro = g.scalar("MacroVariation", 1.0, S, 0, 2)
    spec_base = g.scalar("SpecularBase", 0.5, S, 0, 1)
    sh_mix = g.scalar("ShoulderSetMix", 0.0, "Shoulder", 0, 1)  # 1 = shoulders (zone < 1) use the secondary texture set (ShoulderBaseColorTex ...)
    sh_tint = g.vector("ShoulderTint", (1.0, 0.95, 0.88, 1), "Shoulder")
    sh_tint_amt = g.scalar("ShoulderTintAmount", 0.0, "Shoulder", 0, 1)
    p = {
        "MarkOn": g.scalar("MarkingsEnabled", 1.0, MK, 0, 1),
        "FallLaneW": g.scalar("FallbackLaneWidth", 3.5, MK, 2, 5),
        "UVFlipV": g.scalar("UVFlipV", 1.0, S, 0, 1),
        "CentreStyle": g.scalar("CentreStyle", 0.0, MK, 0, 3),  # 0 dashed, 1 solid, 2 double solid, 3 none
        "EdgeW": g.scalar("EdgeLineWidth", 0.15, MK, 0.05, 0.4),
        "EdgeInset": g.scalar("EdgeLineInset", 0.25, MK, 0, 1),
        "CentreW": g.scalar("CentreLineWidth", 0.15, MK, 0.05, 0.4),
        "LaneLineW": g.scalar("LaneLineWidth", 0.12, MK, 0.05, 0.4),
        "DashLen": g.scalar("DashLength", 3.0, MK, 0.5, 10),
        "DashGap": g.scalar("DashGap", 6.0, MK, 0.5, 20),
        "DashPhase": g.scalar("DashPhase", 0.0, MK, 0, 20),
        "DblGap": g.scalar("DoubleLineGap", 0.12, MK, 0.05, 0.4),
        "Wear": g.scalar("MarkingWear", 0.35, MK, 0, 1),
        "MarkRough": g.scalar("MarkingRoughness", 0.6, MK, 0, 1),
        "TrackDark": g.scalar("WheelTrackDarkening", 0.35, S, 0, 1),
        "TrackSpacing": g.scalar("WheelTrackSpacing", 1.75, S, 1, 2.5),
        "WetResp": g.scalar("WetnessResponse", 1.0, WX, 0, 1),
        "PuddleResp": g.scalar("PuddleResponse", 1.0, WX, 0, 1),
        "RippleStr": g.scalar("RippleStrength", 1.0, WX, 0, 2),
        "SnowResp": g.scalar("SnowResponse", 1.0, WX, 0, 1),
        "SnowClear": g.scalar("SnowRoadClear", 0.75, WX, 0, 1),
        "DustResp": g.scalar("DustResponse", 1.0, WX, 0, 1),
    }
    mark_col = g.vector("MarkingColor", (0.60, 0.60, 0.56, 1), MK)
    centre_col = g.vector("CentreLineColor", (0.60, 0.60, 0.56, 1), MK)
    snow_col = g.vector("SnowColor", (0.80, 0.83, 0.90, 1), WX)
    dust_col = g.vector("DustColor", (0.33, 0.26, 0.17, 1), WX)

    # ---- MPC + noise
    mp = MM.mpc_nodes(g, mpc, ["Wetness", "PuddleAmount", "RainIntensity", "SnowAmount", "DustAmount"])
    tsec = g.time()
    wxy = g.world_pos()["XY"]
    nz_a = g.texture("NoiseTex", noise_path, "linear", wxy * (0.01 / 16.0), "Weather/Noise")["RGBA"]
    nz_b = g.texture("NoiseTex", noise_path, "linear", wxy * (0.01 / 3.1), "Weather/Noise")["RGBA"]
    nz_c = g.texture("NoiseTex", noise_path, "linear", uv1 * (1.0 / 7.0), "Weather/Noise")["RGBA"]

    # ---- uv generation + texture samples (anti-tiling = static switch)
    uvgen = g.custom(UV_GEN, {"TC1": uv1, "TC2": uv2, "Tile": tile, "Across": across, "AntiAmt": anti_amt, "NzA": nz_a},
                     out="float2", extra={"UVB": "float2", "Wt": "float"}, desc="RoadUV")
    smp = MM.pbr_samples(g, uvgen, uvgen["UVB"], pbr, S)
    # secondary (shoulder) set: metric tiling from UV1, switch off = same as the primary set
    uv_sh = uv1 * (1.0 / 4.0)
    bcs = g.texture("ShoulderBaseColorTex", pbr_sh[0], "color", uv_sh, "Shoulder")
    ns = g.texture("ShoulderNormalTex", pbr_sh[1], "normal", uv_sh, "Shoulder")
    orms = g.texture("ShoulderORMTex", pbr_sh[2], "linear", uv_sh, "Shoulder")
    use_sh = "UseShoulderSet"
    sh_bc = g.switch(use_sh, False, bcs["RGB"], smp["bc_a"], "Shoulder")
    sh_n = g.switch(use_sh, False, ns["RGB"], smp["n_a"], "Shoulder")
    sh_orm = g.switch(use_sh, False, orms["RGB"], smp["orm_a"], "Shoulder")

    shade_in = {
        "BCa": smp["bc_a"], "BCb": smp["bc_b"], "Na": smp["n_a"], "Nb": smp["n_b"], "ORMa": smp["orm_a"], "ORMb": smp["orm_b"],
        "BCs": sh_bc, "Ns": sh_n, "ORMs": sh_orm, "ShSetMix": sh_mix, "ShTint": sh_tint, "ShTintAmt": sh_tint_amt,
        "Wt": uvgen["Wt"],
        "NzA": nz_a, "NzB": nz_b, "NzC": nz_c, "TC1": uv1, "TC2": uv2, "TC3": uv3, "Tsec": tsec,
        "Tint": tint, "NormStr": nstr, "RoughScale": rscale, "RoughBias": rbias, "AOStr": aostr, "MacroAmt": macro, "SpecBase": spec_base,
        "Wet": mp["Wetness"], "Puddle": mp["PuddleAmount"], "Rain": mp["RainIntensity"], "Snow": mp["SnowAmount"], "Dust": mp["DustAmount"],
        "MarkCol": mark_col, "CentreCol": centre_col, "SnowCol": snow_col, "DustCol": dust_col,
    }
    shade_in.update(p)
    shade = g.custom(SHADE, shade_in, out="float3", extra={"Normal": "float3", "Rough": "float", "AO": "float", "Spec": "float"}, desc="RoadShade")

    g.out(MP.MP_BASE_COLOR, shade)
    g.out(MP.MP_NORMAL, shade["Normal"])
    g.out(MP.MP_ROUGHNESS, shade["Rough"])
    g.out(MP.MP_AMBIENT_OCCLUSION, shade["AO"])
    g.out(MP.MP_SPECULAR, shade["Spec"])
    return MM.finish(g, name)


BUILDERS = {"M_Roam_Road": build_road}
