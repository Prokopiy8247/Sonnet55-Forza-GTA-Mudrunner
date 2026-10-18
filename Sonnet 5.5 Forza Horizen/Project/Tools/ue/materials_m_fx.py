"""Water + FX masters.

  M_Roam_Water_Simple   sea / lake surface (Single Layer Water when it compiles under Substrate, else a depth-faded translucent fallback)
  M_Roam_Water_River    same graph, river tuning (clearer, faster, small waves; UV0-flow option)
  M_Roam_Particle_Soft  lit soft-particle sprite (dust / smoke) for Niagara sprites: sprite texture x tint x ParticleColor, depth + near fade
  M_Roam_Particle_Unlit unlit variant (sparks, glow, light shafts; instance may switch blend to additive)
  M_Roam_Skid           deferred decal for tyre marks / skid marks (strip texture tiling along the decal's long axis)
Parameter names: Docs/Tech/MATERIALS.md
"""
import os
import sys

import unreal

_HERE = os.path.dirname(os.path.abspath(globals().get("__file__", unreal.Paths.project_dir() + "Tools/ue/materials_m_fx.py")))
if _HERE not in sys.path:
    sys.path.insert(0, _HERE)
import materials_lib as L  # noqa: E402
from materials_lib import Graph, MAT_ROOT, MP, load, new_material, warn  # noqa: E402
import materials_masters as MM  # noqa: E402
import materials_textures as T  # noqa: E402

# ------------------------------------------------------------------------------------------------------------------------------
# water
# ------------------------------------------------------------------------------------------------------------------------------
WATER_UV = """
float t = Tsec * Speed;
float3 wd = float3(WDir.x, WDir.y, 0.0);
float wl = length(wd.xy);
float2 d2 = (wl > 1e-3) ? wd.xy / wl : float2(1.0, 0.0);
float2 p = (UVMode > 0.5) ? TC0 : WP.xy * 0.01;
float2 pm = p;
float2 d3 = float2(-d2.y, d2.x);
UVB = (pm / max(TileB, 0.1)) + (d2 * 0.7 + d3 * 0.35) * t * 0.55 + float2(0.37, 0.61);
UVC = (pm / max(TileA * 0.37, 0.1)) + (-d2 * 0.4 + d3 * 0.8) * t * 0.9 + float2(0.71, 0.13);
return (pm / max(TileA, 0.1)) + d2 * t * 0.35;
"""

WATER_SHADE = """
float3 nA = NA * 2.0 - 1.0;
float3 nB = NB * 2.0 - 1.0;
float3 nC = NC * 2.0 - 1.0;
float dist = distance(CamP, WPos) * 0.01;
float farF = saturate(1.0 - (dist - FlatStart) / max(FlatEnd - FlatStart, 1.0));
float rainK = 1.0 + Rain * 0.6;
float2 nxy = (nA.xy * WaveA + nB.xy * WaveB + nC.xy * WaveC) * NStr * rainK * lerp(0.15, 1.0, farF);
float3 Normal = normalize(float3(nxy, 1.0));
float3 V = normalize(CamP - WPos);
float ndv = saturate(dot(Normal, V));
float fres = pow(1.0 - ndv, 5.0);
Fres = fres;
// sparkle / white caps from the crest noise
float cap = smoothstep(CapThresh, CapThresh + 0.12, NzA.a * 0.6 + NzA.r * 0.5 + (nxy.x + nxy.y) * 0.35) * CapAmt * (0.3 + WindK);
Foam = saturate(cap) * farF;
return Normal;
"""


def _water_graph(g, river):
    mpc = load(MM.MPC_PATH)
    S, WV, FM = "Water", "Waves", "Foam"
    p = {
        "Speed": g.scalar("FlowSpeed", 0.5 if not river else 1.6, WV, 0, 8),
        "TileA": g.scalar("TileMetresA", 8.0, WV, 0.5, 64),
        "TileB": g.scalar("TileMetresB", 4.0, WV, 0.5, 64),
        "NStr": g.scalar("NormalStrength", 0.9 if not river else 1.0, WV, 0, 3),
        "WaveA": g.scalar("WaveWeightA", 1.0, WV, 0, 2),
        "WaveB": g.scalar("WaveWeightB", 0.8, WV, 0, 2),
        "WaveC": g.scalar("WaveWeightC", 0.35, WV, 0, 2),
        "UVMode": g.scalar("UseMeshUV", 0.0 if not river else 0.0, WV, 0, 1),
        "FlatStart": g.scalar("FlattenStartMetres", 60.0, WV, 1, 2000),
        "FlatEnd": g.scalar("FlattenEndMetres", 900.0, WV, 2, 6000),
        "CapAmt": g.scalar("WhiteCapAmount", 0.25 if not river else 0.12, FM, 0, 1),
        "CapThresh": g.scalar("WhiteCapThreshold", 0.72, FM, 0, 1.5),
    }
    return mpc, p


def _fresh_material(path, **props):
    """new_material + guarantee that no expression survived the wipe (custom-output nodes such as the Single Layer Water output can survive
    delete_all_material_expressions; a second SLW node is a compile error): if any is left the asset is deleted and created again."""
    m = new_material(path, **props)
    n = L.mel.get_num_material_expressions(m)
    if n:
        warn("%s: %d expression(s) survived the wipe, recreating the asset" % (path, n))
        L.ea.delete_asset(path)
        m = new_material(path, **props)
    return m


def _connect_first(src, node, names):
    """Connect `src` to the first input pin name of `node` that the engine accepts (pin names of rarely used nodes differ between versions)."""
    for n in names:
        if L.mel.connect_material_expressions(src.x, src.o, node.x, n):
            return n
    raise RuntimeError("no input pin of %s accepted any of %s" % (type(node.x).__name__, names))


def _depth_fade(g, dist):
    """0 at the surface behind which nothing is, 1 when the scene is `dist` cm (or more) behind this pixel (soft particles / water depth)."""
    return g.custom("return saturate((SD - PD) / max(Dist, 1.0));", {"SD": g.node("SceneDepth"), "PD": g.node("PixelDepth"), "Dist": dist}, out="float",
                    desc="DepthFade")


def _build_water(name, river):
    """Build with Single Layer Water first; if it does not compile, rebuild as a depth-faded translucent surface."""
    for mode in ("slw", "translucent"):
        if mode == "slw":   # Single Layer Water renders in its own pass: the material must be opaque (no Opacity input)
            m = _fresh_material(MAT_ROOT + "/" + name, blend_mode=unreal.BlendMode.BLEND_OPAQUE, two_sided=False,
                                shading_model=unreal.MaterialShadingModel.MSM_SINGLE_LAYER_WATER)
        else:
            m = _fresh_material(MAT_ROOT + "/" + name, blend_mode=unreal.BlendMode.BLEND_TRANSLUCENT, two_sided=False)
            m.set_editor_property("translucency_lighting_mode", unreal.TranslucencyLightingMode.TLM_SURFACE_PER_PIXEL_LIGHTING)
        g = Graph(m)
        mpc, p = _water_graph(g, river)
        S = "Water"
        uv0 = g.texcoord(0)
        wdir = g.mpc(mpc, "WindDirection")
        rain = g.mpc(mpc, "RainIntensity")
        windk = g.mpc(mpc, "WindStrength")
        tsec = g.time()
        wp = g.world_pos()["XYZ"]
        uvs = g.custom(WATER_UV, {"Tsec": tsec, "Speed": p["Speed"], "WDir": wdir, "TC0": uv0, "WP": wp, "UVMode": p["UVMode"], "TileA": p["TileA"],
                                  "TileB": p["TileB"]}, out="float2", extra={"UVB": "float2", "UVC": "float2"}, desc="WaterUV")
        na = g.texture("WaveNormalA", T.tex_path("water_normal_a", "N"), "normal", uvs, S)["RGB"]
        nb = g.texture("WaveNormalB", T.tex_path("water_normal_b", "N"), "normal", uvs["UVB"], S)["RGB"]
        nc = g.texture("WaveNormalB", T.tex_path("water_normal_b", "N"), "normal", uvs["UVC"], S)["RGB"]
        # custom shade expects 0..1 packed values: re-pack the unpacked normals
        packed = lambda n: n * 0.5 + 0.5
        noise = MM.noise_tex(g, wp["XY"] * (0.01 / 24.0) + g.custom("return float2(T * 0.004, T * 0.0027);", {"T": tsec}, out="float2", desc="Drift"))
        sh = g.custom(WATER_SHADE, {
            "NA": packed(na), "NB": packed(nb), "NC": packed(nc), "CamP": g.camera_pos(), "WPos": wp, "NzA": noise, "Rain": rain, "WindK": windk,
            **{k: p[k] for k in ("FlatStart", "FlatEnd", "WaveA", "WaveB", "WaveC", "NStr", "CapAmt", "CapThresh")},
        }, out="float3", extra={"Fres": "float", "Foam": "float"}, desc="WaterShade")
        shallow = g.vector("ShallowColor", (0.04, 0.22, 0.24, 1) if not river else (0.08, 0.2, 0.15, 1), S)
        deep = g.vector("DeepColor", (0.01, 0.06, 0.12, 1) if not river else (0.03, 0.09, 0.07, 1), S)
        rough = g.scalar("Roughness", 0.04, S, 0, 1)
        spec = g.scalar("SpecularBase", 0.5, S, 0, 1)
        foam_col = g.vector("FoamColor", (0.8, 0.85, 0.9, 1), S)
        if mode == "slw":
            scat = g.vector("ScatteringColor", (0.004, 0.012, 0.014, 1) if not river else (0.01, 0.02, 0.012, 1), S)
            absorb = g.vector("AbsorptionColor", (0.40, 0.09, 0.05, 1) if not river else (0.6, 0.22, 0.2, 1), S)
            dens = g.scalar("DensityScale", 1.0 if not river else 2.0, S, 0.05, 10)
            slw = g.node("SingleLayerWaterMaterialOutput")
            _connect_first(scat.rgb * dens, slw, ("Scattering Coefficients", "ScatteringCoefficients", "Scattering"))
            _connect_first(absorb.rgb * dens, slw, ("Absorption Coefficients", "AbsorptionCoefficients", "Absorption"))
            _connect_first(g.c(0.0), slw, ("Phase G", "PhaseG"))
            g.out(MP.MP_BASE_COLOR, foam_col.rgb * sh["Foam"])
            g.out(MP.MP_NORMAL, sh)
            g.out(MP.MP_ROUGHNESS, g.lerp(rough, g.c(0.6), sh["Foam"]))
            g.out(MP.MP_SPECULAR, spec)
            g.out(MP.MP_METALLIC, 0.0)
        else:
            sdepth = g.scalar("DepthScaleCm", 600.0, S, 20, 5000)
            fade = _depth_fade(g, sdepth)
            col = g.lerp(shallow.rgb, deep.rgb, fade)
            col = g.lerp(col, foam_col.rgb, sh["Foam"])
            g.out(MP.MP_BASE_COLOR, col * 0.8)
            g.out(MP.MP_EMISSIVE_COLOR, col * 0.15)
            g.out(MP.MP_NORMAL, sh)
            g.out(MP.MP_ROUGHNESS, g.lerp(rough, g.c(0.6), sh["Foam"]))
            g.out(MP.MP_SPECULAR, spec)
            g.out(MP.MP_METALLIC, 0.0)
            g.out(MP.MP_OPACITY, g.lerp(g.c(0.55), g.c(0.97), fade) + sh["Fres"] * 0.3)
        errs = MM.finish(g, name + (" [%s]" % mode))
        if not errs:
            L.log("%s built as %s" % (name, mode))
            return errs
        warn("%s: mode %s failed to compile, %s" % (name, mode, "trying fallback" if mode == "slw" else "no fallback left"))
    return errs


def build_water_simple():
    return _build_water("M_Roam_Water_Simple", False)


def build_water_river():
    return _build_water("M_Roam_Water_River", True)


# ------------------------------------------------------------------------------------------------------------------------------
# particles
# ------------------------------------------------------------------------------------------------------------------------------
def _build_particle(name, lit):
    m = new_material(MAT_ROOT + "/" + name, blend_mode=unreal.BlendMode.BLEND_TRANSLUCENT, two_sided=True,
                     used_with_niagara_sprites=True, used_with_niagara_ribbons=True, used_with_niagara_mesh_particles=True)
    if lit:
        m.set_editor_property("translucency_lighting_mode", unreal.TranslucencyLightingMode.TLM_VOLUMETRIC_NON_DIRECTIONAL)
    else:
        m.set_editor_property("shading_model", unreal.MaterialShadingModel.MSM_UNLIT)
    g = Graph(m)
    S = "Particle"
    uv = g.texcoord(0)
    tex = g.texture("SpriteTex", T.tex_path("dust_puff_sprite", "BC"), "color", uv, S)
    tint = g.vector("Tint", (1, 1, 1, 1), S)
    op_scale = g.scalar("OpacityScale", 1.0, S, 0, 4)
    soft = g.scalar("SoftDepthCm", 120.0, S, 1, 1000)
    near = g.scalar("NearFadeCm", 60.0, S, 0, 500)
    use_pc = g.scalar("UseParticleColor", 1.0, S, 0, 1)
    pc = g.node("ParticleColor")
    pc_rgb = g.lerp(g.c3(1, 1, 1), pc.rgb, use_pc)
    pc_a = g.lerp(g.c(1.0), pc["A"], use_pc)
    color = tex["RGB"] * tint.rgb * pc_rgb
    pix = g.node("PixelDepth")
    near_f = g.sat((pix - near) / g.mx(near, g.c(1.0)))
    alpha = tex["A"] * tint["A"] * pc_a * op_scale * near_f
    alpha = g.sat(alpha) * _depth_fade(g, soft)
    if lit:
        glow = g.scalar("SelfGlow", 0.1, S, 0, 4)
        g.out(MP.MP_BASE_COLOR, color)
        g.out(MP.MP_EMISSIVE_COLOR, color * glow)
        g.out(MP.MP_ROUGHNESS, 1.0)
        g.out(MP.MP_SPECULAR, 0.0)
        g.out(MP.MP_METALLIC, 0.0)
    else:
        bright = g.scalar("Brightness", 1.0, S, 0, 50)
        g.out(MP.MP_EMISSIVE_COLOR, color * bright)
    g.out(MP.MP_OPACITY, alpha)
    return MM.finish(g, name)


def build_particle_soft():
    return _build_particle("M_Roam_Particle_Soft", True)


def build_particle_unlit():
    return _build_particle("M_Roam_Particle_Unlit", False)


# ------------------------------------------------------------------------------------------------------------------------------
# skid decal
# ------------------------------------------------------------------------------------------------------------------------------
SKID = """
float2 uv = float2(TC.x, TC.y * Tiles);
float edge = smoothstep(0.0, EdgeFade, TC.y) * smoothstep(1.0, 1.0 - EdgeFade, TC.y);
edge *= smoothstep(0.0, 0.08, TC.x) * smoothstep(1.0, 0.92, TC.x);
Edge = edge;
return uv;
"""


def build_skid():
    name = "M_Roam_Skid"
    m = new_material(MAT_ROOT + "/" + name, blend_mode=unreal.BlendMode.BLEND_TRANSLUCENT, material_domain=unreal.MaterialDomain.MD_DEFERRED_DECAL)
    g = Graph(m)
    S = "Skid"
    tc = g.texcoord(0)
    tiles = g.scalar("TilesAlong", 4.0, S, 0.25, 40)
    edge_fade = g.scalar("EdgeFade", 0.08, S, 0.001, 0.5)
    sk = g.custom(SKID, {"TC": tc, "Tiles": tiles, "EdgeFade": edge_fade}, out="float2", extra={"Edge": "float"}, desc="SkidUV")
    tex = g.texture("MarkBaseColorTex", T.tex_path("tire_mark", "BC"), "color", sk, S)
    nrm = g.texture("MarkNormalTex", T.tex_path("tire_mark", "N"), "normal", sk, S)
    orm = g.texture("MarkORMTex", T.tex_path("tire_mark", "ORM"), "linear", sk, S)
    tint = g.vector("Tint", (1, 1, 1, 1), S)
    opac = g.scalar("Opacity", 1.0, S, 0, 1)  # runtime fade-out
    strength = g.scalar("OpacityScale", 1.0, S, 0, 2)
    nstr = g.scalar("NormalStrength", 0.6, S, 0, 2)
    rough_scale = g.scalar("RoughnessScale", 1.0, S, 0, 2)
    wet = g.mpc(load(MM.MPC_PATH), "Wetness")
    g.out(MP.MP_BASE_COLOR, tex["RGB"] * tint.rgb * g.lerp(g.c(1.0), g.c(0.8), wet))
    g.out(MP.MP_OPACITY, g.sat(tex["A"] * tint["A"] * opac * strength * sk["Edge"]))
    g.out(MP.MP_NORMAL, g.append(nrm["RGB"].rg * nstr, nrm["RGB"].b))
    g.out(MP.MP_ROUGHNESS, g.sat(orm["RGB"].g_ * rough_scale))
    g.out(MP.MP_SPECULAR, 0.4)
    g.out(MP.MP_METALLIC, 0.0)
    return MM.finish(g, name)


# ------------------------------------------------------------------------------------------------------------------------------
# post-process rain-on-lens overlay (optional): refracting droplets + short trails, density from MPC RainIntensity
# ------------------------------------------------------------------------------------------------------------------------------
RAIN_PP = """
float aspect = max(VS.x, 1.0) / max(VS.y, 1.0);
float dens = saturate(Rain * RainScale);
float2 off = float2(0.0, 0.0);
float shade = 0.0;
float hi = 0.0;
[unroll]
for (int L = 0; L < 2; L++)
{
    float sc = (L == 0) ? 1.0 : 1.7;
    float2 q = UV * float2(Cells * aspect, Cells) * sc + float2(L * 13.7, L * 7.1);
    float2 id = floor(q);
    float2 f = frac(q) - 0.5;
    float h1 = frac(sin(dot(id, float2(127.1, 311.7))) * 43758.5453);
    float h2 = frac(sin(dot(id, float2(269.5, 183.3))) * 43758.5453);
    float h3 = frac(sin(dot(id, float2(419.2, 371.9))) * 43758.5453);
    float present = step(h1, dens * ((L == 0) ? 0.55 : 0.4));
    float life = frac(Tsec * (0.025 + 0.04 * h3) + h2);
    float2 c = float2((h2 - 0.5) * 0.45, lerp(0.40, -0.40, life * life));
    float r = (0.13 + 0.09 * h3) * lerp(1.0, 0.45, life);
    float2 dv = f - c;
    float d = length(dv * float2(1.0, 0.85));
    float drop = smoothstep(r, r * 0.55, d) * present;
    float trail = smoothstep(r * 0.30, 0.0, abs(f.x - c.x)) * step(c.y, f.y) * smoothstep(c.y + 0.45, c.y, f.y) * 0.5 * step(0.55, h1) * present;
    off += -(dv / max(r, 1e-3)) * drop * Strength;
    shade += drop * 0.30 * (1.0 - smoothstep(0.0, r, d) * 0.5);
    hi += smoothstep(r * 0.35, 0.0, length(dv - float2(-0.04, -0.05) * r * 4.0)) * drop;
    off += float2(0.0, 0.0) * trail;
    shade += trail * 0.10;
}
Offset = off * 0.035;
Shade = shade;
Hi = hi;
return dens;
"""


def build_pp_rain():
    name = "M_Roam_PP_RainOverlay"
    m = new_material(MAT_ROOT + "/" + name, material_domain=unreal.MaterialDomain.MD_POST_PROCESS,
                     blendable_location=unreal.BlendableLocation.BL_SCENE_COLOR_AFTER_TONEMAPPING)
    g = Graph(m)
    S = "Rain lens"
    cells = g.scalar("DropCells", 9.0, S, 3, 30)
    strength = g.scalar("RefractionStrength", 1.0, S, 0, 3)
    rain_scale = g.scalar("RainScale", 1.5, S, 0, 4)
    mpc = load(MM.MPC_PATH)
    rain = g.mpc(mpc, "RainIntensity")
    scr = g.node("ScreenPosition")
    uv = scr["ViewportUV"]
    vs = g.node("ViewSize")
    tsec = g.time()
    r = g.custom(RAIN_PP, {"UV": uv, "VS": vs, "Tsec": tsec, "Rain": rain, "RainScale": rain_scale, "Cells": cells, "Strength": strength},
                 out="float", extra={"Offset": "float2", "Shade": "float", "Hi": "float"}, desc="RainDrops")
    st = g.node("SceneTexture", {"scene_texture_id": unreal.SceneTextureId.PPI_POST_PROCESS_INPUT0, "filtered": True})
    _connect_first(uv + r["Offset"], st, ("Coordinates", "UVs", "UV"))
    col = st["Color"] * (1.0 - r["Shade"]) + r["Hi"] * 0.25
    g.out(MP.MP_EMISSIVE_COLOR, col)
    return MM.finish(g, name)


BUILDERS = {
    "M_Roam_Water_Simple": build_water_simple,
    "M_Roam_Water_River": build_water_river,
    "M_Roam_Particle_Soft": build_particle_soft,
    "M_Roam_Particle_Unlit": build_particle_unlit,
    "M_Roam_Skid": build_skid,
    "M_Roam_PP_RainOverlay": build_pp_rain,
}
