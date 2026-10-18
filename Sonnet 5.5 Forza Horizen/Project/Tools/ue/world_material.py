"""world_material - builds  /Game/Forza/Materials/Landscape/M_Roam_Landscape  (the terrain master) with MaterialEditingLibrary.   Docs/Tech/WORLD_BUILD.md

Design (see WORLD_BUILD.md section 'Landscape material'):
  * 8 weight-blended landscape layers (LandscapeLayerSample nodes, names = world_meta.json layers.order):
        Grass ForestFloor Farmland Rock Sand RedClay Snow RoadVerge
    each backed by the procedural texture sets that the materials agent imported (/Game/Forza/Textures/Terrain/T_<set>_BC|N|ORM).
  * All texture UVs come from the WORLD position (tile size = the manifest metres), no mesh UVs: the same material works for every proxy,
    for Nanite and non-Nanite, and nothing stretches on steep terrain because steep ground switches to a triplanar cliff rock.
  * Anti-tiling: every large-area layer samples its colour twice (near + a rotated 5.3x larger copy) and mixes them with tileable noise;
    a 3-scale noise (30 m, 140 m, 900 m) breaks up the colour, the wheat/soil, lush/dry grass, beach/desert sand and warm/grey rock splits.
  * Layer transitions are sharpened with the AO channel as a height proxy (height blending), so the 1 m weight maps do not look like gradients.
  * One HLSL Custom node does the blending (50 texture samples, ~2 ms at 4K on a mid GPU is the budget; measured numbers in WORLD_BUILD.md).
  * Wetness comes from MPC_Roam_World (darker, glossier ground).
All samplers are 'shared wrap' (no per-texture sampler slots: the 16-sampler limit does not apply).
"""
import unreal

import world_lib as W

mel = unreal.MaterialEditingLibrary
MP = unreal.MaterialProperty
CMOT = unreal.CustomMaterialOutputType

TERRAIN = W.TEX_ROOT + "/Terrain"
FX = W.TEX_ROOT + "/FX"

# prefix -> (texture set, tile metres, kinds sampled)  kinds: c = colour near, f = colour far (rotated, 5.3x), n = normal, o = ORM
SETS = {
    "gl": ("grass_lush", 4.0, "cfno"),
    "gd": ("grass_dry", 4.0, "c"),
    "ff": ("forest_floor", 3.0, "cfno"),
    "fm": ("farmland_soil", 6.0, "cfno"),
    "fw": ("field_wheat", 4.0, "cno"),
    "rg": ("rock_grey", 4.0, "cfno"),
    "bs": ("beach_sand", 3.0, "cno"),
    "ds": ("desert_sand", 4.0, "cfno"),
    "rd": ("red_clay", 4.0, "cfno"),
    "sn": ("snow", 4.0, "cno"),
    "gr": ("gravel", 2.0, "cno"),
    "dr": ("dirt_road", 4.0, "cno"),
}
CLIFF = ("rock_cliff", 8.0)
NOISE = (FX + "/T_tileable_perlin_noise_D", [("nz1", 30.0), ("nz2", 140.0), ("nz3", 900.0)])
WEIGHTS = [("w_grass", "Grass"), ("w_forest", "ForestFloor"), ("w_farm", "Farmland"), ("w_rock", "Rock"),
           ("w_sand", "Sand"), ("w_clay", "RedClay"), ("w_snow", "Snow"), ("w_verge", "RoadVerge")]

SAMPLER = {
    "c": unreal.MaterialSamplerType.SAMPLERTYPE_COLOR,
    "f": unreal.MaterialSamplerType.SAMPLERTYPE_COLOR,
    "n": unreal.MaterialSamplerType.SAMPLERTYPE_NORMAL,
    "o": unreal.MaterialSamplerType.SAMPLERTYPE_LINEAR_COLOR,   # ORM assets are BC7 linear (not 'Masks' compression)
    "d": unreal.MaterialSamplerType.SAMPLERTYPE_LINEAR_COLOR,
}
KIND_SUFFIX = {"c": "BC", "f": "BC", "n": "N", "o": "ORM"}


# ---------------------------------------------------------------------------------------------------------------------------
HLSL_UV = r"""
// world-space UVs (metres). Every texture gets its own tile size; 'f' sets are rotated 27 degrees and 5.3x larger (anti-tiling).
float2 p = WP.xy * 0.01;
float cs = 0.8910;
float sn_ = 0.4540;
float2 r = float2(p.x * cs - p.y * sn_, p.x * sn_ + p.y * cs);
float zz = -WP.z * 0.01;
%(body)s
return p;
"""

HLSL_SHADE = r"""
// ---------------------------------------------------------------------------------------------------------------------
// Roamline terrain shading. Inputs: layer weights w_*, textures, noise nz1..3, world position, vertex normal, pixel depth, wetness
// ---------------------------------------------------------------------------------------------------------------------
float depthM = PDepth * 0.01;
float zM = WP.z * 0.01;
float3 N0v = normalize(VN);
// The heightmap is 16 bit (2.34 cm per step): on very gentle ground (beaches, plains) the quantisation terraces tilt the vertex normal by ~1.3 degrees
// every few metres and show up as long light/dark bands. Ground flatter than ~2 degrees is shaded as a smooth plane, the effect fades out to 5.5 degrees.
float flatK = (1.0 - smoothstep(0.0004, 0.0045, 1.0 - N0v.z)) * 0.92;
float3 N0 = normalize(lerp(N0v, float3(0.0, 0.0, 1.0), flatK));
float slope = saturate(1.0 - N0.z);                  // 0 flat .. 1 vertical

float fineN = nz1.g;                                  // ~30 m features
float macroMid = nz2.r;                               // ~140 m patches (fields, dry/lush patches)
float macroLarge = nz3.r;                             // ~900 m regions
float tiling = saturate(fineN * 1.7 - 0.25);          // mix toward the far (rotated) colour sample

// ---- per-layer surfaces (colour, roughness, ao, normal xy) -------------------------------------------------------------
float dryMix = smoothstep(120.0, 260.0, zM + (macroMid - 0.5) * 70.0) * 0.85;
float3 cGrass = lerp(lerp(gl_c, gl_cf, tiling), gd_c, dryMix);
float3 cForest = lerp(ff_c, ff_cf, tiling);
float wheatMask = smoothstep(0.44, 0.56, macroMid);
float3 cFarm = lerp(lerp(fm_c, fm_cf, tiling), fw_c, wheatMask);
float rockWarm = 1.0 - smoothstep(300.0, 400.0, zM + (macroMid - 0.5) * 90.0);
float3 cRock = lerp(rg_c, rg_cf, tiling);
float beachMix = 1.0 - smoothstep(5.0, 16.0, zM + (macroMid - 0.5) * 10.0);
float3 cSand = lerp(lerp(ds_c, ds_cf, tiling), bs_c, beachMix);
float3 cClay = lerp(rd_c, rd_cf, tiling);
float3 cSnow = sn_c;
float3 cVerge = lerp(gr_c, dr_c, saturate(fineN * 1.4 - 0.1));

float3 oGrass = gl_o;
float3 oForest = ff_o;
float3 oFarm = lerp(fm_o, fw_o, wheatMask);
float3 oRock = rg_o;
float3 oSand = lerp(ds_o, bs_o, beachMix);
float3 oClay = rd_o;
float3 oSnow = sn_o;
float3 oVerge = lerp(gr_o, dr_o, saturate(fineN * 1.4 - 0.1));

float2 nGrass = gl_n.xy;
float2 nForest = ff_n.xy;
float2 nFarm = lerp(fm_n.xy, fw_n.xy, wheatMask);
float2 nRock = rg_n.xy;
float2 nSand = lerp(ds_n.xy, bs_n.xy, beachMix);
float2 nClay = rd_n.xy;
float2 nSnow = sn_n.xy;
float2 nVerge = lerp(gr_n.xy, dr_n.xy, saturate(fineN * 1.4 - 0.1));

// ---- height blending: ORM.r (ambient occlusion) is the height proxy -------------------------------------------------------
float ws = w_grass + w_forest + w_farm + w_rock + w_sand + w_clay + w_snow + w_verge + 1e-4;
float k0 = w_grass / ws * (0.45 + oGrass.r);
float k1 = w_forest / ws * (0.45 + oForest.r);
float k2 = w_farm / ws * (0.45 + oFarm.r);
float k3 = w_rock / ws * (0.45 + oRock.r);
float k4 = w_sand / ws * (0.45 + oSand.r);
float k5 = w_clay / ws * (0.45 + oClay.r);
float k6 = w_snow / ws * (0.45 + oSnow.r);
float k7 = w_verge / ws * (0.45 + oVerge.r);
k0 *= k0; k1 *= k1; k2 *= k2; k3 *= k3; k4 *= k4; k5 *= k5; k6 *= k6; k7 *= k7;
float ks = k0 + k1 + k2 + k3 + k4 + k5 + k6 + k7 + 1e-6;
k0 /= ks; k1 /= ks; k2 /= ks; k3 /= ks; k4 /= ks; k5 /= ks; k6 /= ks; k7 /= ks;

float3 albedo = cGrass * k0 + cForest * k1 + cFarm * k2 + cRock * k3 + cSand * k4 + cClay * k5 + cSnow * k6 + cVerge * k7;
float rough = oGrass.g * k0 + oForest.g * k1 + oFarm.g * k2 + oRock.g * k3 + oSand.g * k4 + oClay.g * k5 + oSnow.g * k6 + oVerge.g * k7;
float ao = oGrass.r * k0 + oForest.r * k1 + oFarm.r * k2 + oRock.r * k3 + oSand.r * k4 + oClay.r * k5 + oSnow.r * k6 + oVerge.r * k7;
float2 nxy = nGrass * k0 + nForest * k1 + nFarm * k2 + nRock * k3 + nSand * k4 + nClay * k5 + nSnow * k6 + nVerge * k7;

// ---- steep ground: triplanar sedimentary cliff rock (warm below ~340 m, grey granite above) --------------------------------------
float steep = smoothstep(0.22, 0.42, slope + (fineN - 0.5) * 0.10);
float3 bw = pow(abs(N0v), 10.0);                  // sharper planar blend: two planar strata projections overlapping make a brick-like moire
bw /= (bw.x + bw.y + bw.z + 1e-4);                   // x: face normal along X (YZ projection), y: XZ, z: XY
float3 cCliff = rc_cx * bw.x + rc_cy * bw.y + rc_cz * bw.z;
float cliffGrey = smoothstep(300.0, 430.0, zM + (macroMid - 0.5) * 80.0);
float cliffLum = dot(cCliff, float3(0.299, 0.587, 0.114));
cCliff = lerp(cCliff, float3(cliffLum, cliffLum * 1.02, cliffLum * 1.06) * 1.05, cliffGrey * 0.75);
float3 pwCliff = bw.x * float3(0.0, rc_nx.x, -rc_nx.y) + bw.y * float3(rc_ny.x, 0.0, -rc_ny.y) + bw.z * float3(rc_nz.x, rc_nz.y, 0.0);
// the rock LAYER on gentle slopes: warm cliff rock below the grey-rock line (planar rock_grey tinted warm), blended by rockWarm
albedo = lerp(albedo, albedo * float3(1.18, 1.0, 0.82), rockWarm * k3);
albedo = lerp(albedo, cCliff, steep);
rough = lerp(rough, rc_o.g, steep);
ao = lerp(ao, rc_o.r, steep);

// ---- macro variation, wetness, distance ------------------------------------------------------------------------------------
float macroTint = lerp(0.86, 1.14, macroMid) * lerp(0.94, 1.06, macroLarge) * lerp(0.96, 1.04, fineN);
albedo *= macroTint;
albedo = lerp(albedo, albedo * albedo * 1.6, Wet * 0.5);   // wet ground: darker / more saturated
rough = lerp(rough, rough * 0.4 + 0.08, Wet);
rough = saturate(rough + saturate((depthM - 400.0) / 2500.0) * 0.12);   // distant ground: less sparkle

float nStrength = lerp(1.0, 0.30, saturate((depthM - 60.0) / 600.0));
float3 pw = float3(nxy, 0.0) * (1.0 - steep) + pwCliff * steep;
float3 wn = normalize(N0 + pw * nStrength);
Normal = normalize(mul(Parameters.TangentToWorld, wn));     // world -> tangent space of the landscape vertex frame
AO = saturate(lerp(1.0, ao, 0.85));
return float4(albedo, saturate(rough));
"""


class Builder(object):
    def __init__(self, mat):
        self.m = mat
        self.n = 0

    def node(self, cls, props=None, x=None, y=None):
        klass = getattr(unreal, "MaterialExpression" + cls)
        self.n += 1
        if x is None:
            x = -1800
        if y is None:
            y = self.n * 90
        e = mel.create_material_expression(self.m, klass, x, y)
        for k, v in (props or {}).items():
            e.set_editor_property(k, v)
        return e

    def connect(self, src, src_out, dst, dst_in):
        if not mel.connect_material_expressions(src, src_out, dst, dst_in):
            raise RuntimeError("connect failed: %s[%s] -> %s.%s" % (type(src).__name__, src_out, type(dst).__name__, dst_in))

    def custom(self, code, inputs, out_type, extra=None, desc="", x=-1000, y=0):
        """inputs: ordered list of (name, src_expression, src_output). extra: list of (name, type)."""
        e = mel.create_material_expression(self.m, unreal.MaterialExpressionCustom, x, y)
        cis = []
        for name, _, _ in inputs:
            ci = unreal.CustomInput()
            ci.set_editor_property("input_name", name)
            cis.append(ci)
        e.set_editor_property("inputs", cis)
        e.set_editor_property("code", code)
        e.set_editor_property("output_type", out_type)
        e.set_editor_property("description", desc)
        if extra:
            outs = []
            for name, t in extra:
                co = unreal.CustomOutput()
                co.set_editor_property("output_name", name)
                co.set_editor_property("output_type", t)
                outs.append(co)
            e.set_editor_property("additional_outputs", outs)
        for name, src, src_out in inputs:
            self.connect(src, src_out, e, name)
        return e


def _tex_path(setname, kind):
    return "%s/T_%s_%s" % (TERRAIN, setname, KIND_SUFFIX[kind])


def build(path=None):
    """(Re)builds the material; returns the list of compile error strings."""
    path = path or W.LANDSCAPE_MAT
    d, n = path.rsplit("/", 1)
    W.ensure_dir(d)
    if W.ea.does_asset_exist(path):
        mat = W.load(path)
        mel.delete_all_material_expressions(mat)
    else:
        mat = W.tools.create_asset(n, d, unreal.Material, unreal.MaterialFactoryNew())
    mat.set_editor_property("material_domain", unreal.MaterialDomain.MD_SURFACE)
    mat.set_editor_property("blend_mode", unreal.BlendMode.BLEND_OPAQUE)
    mat.set_editor_property("shading_model", unreal.MaterialShadingModel.MSM_DEFAULT_LIT)
    mat.set_editor_property("two_sided", False)
    for flag in ("used_with_nanite",):
        try:
            mat.set_editor_property(flag, True)
        except Exception as exc:  # noqa: BLE001
            W.warn("material flag %s: %r" % (flag, exc))

    b = Builder(mat)

    # ---- inputs: world position, vertex normal, pixel depth, wetness, layer weights ---------------------------------------------
    wp = b.node("WorldPosition", y=0)
    vn = b.node("VertexNormalWS", y=100)
    depth = b.node("PixelDepth", y=200)
    if W.ea.does_asset_exist(W.MPC_PATH):
        wet = b.node("CollectionParameter", {"collection": W.load(W.MPC_PATH), "parameter_name": "Wetness"}, y=300)
        wet_out = ""
    else:
        W.warn("MPC_Roam_World missing - wetness fixed to 0")
        wet = b.node("Constant", {"r": 0.0}, y=300)
        wet_out = ""
    layer_nodes = []
    for var, layer in WEIGHTS:
        ls = b.node("LandscapeLayerSample", {"parameter_name": layer, "preview_weight": 1.0 if layer == "Grass" else 0.0}, y=400 + len(layer_nodes) * 90)
        layer_nodes.append((var, ls))

    # ---- UV generator -------------------------------------------------------------------------------------------------------
    uv_lines = []
    uv_outputs = []
    for prefix, (setname, tile, kinds) in SETS.items():
        uv_lines.append("UV_%s = p / %.4f;" % (prefix, tile))
        uv_outputs.append("UV_" + prefix)
        if "f" in kinds:
            uv_lines.append("UVF_%s = r / %.4f + float2(0.37, 0.61);" % (prefix, tile * 5.3))
            uv_outputs.append("UVF_" + prefix)
    # cliff projections get a slow analytic domain warp (wavelengths 35-110 m, +-3 m / +-1.2 m): one 8 m tile of strata + cracks repeated in a regular grid
    # looks like a woven plaid from a distance; the warp makes the strata undulate and the vertical cracks drift instead of repeating
    uv_lines.append("float2 wx = float2(p.y, zz);")
    uv_lines.append("float2 wy = float2(p.x, zz);")
    uv_lines.append("float2 dx = float2(3.0 * sin(zz * 0.083 + p.y * 0.031) + 1.8 * sin(zz * 0.19 - p.y * 0.057 + 1.7), "
                    "1.2 * sin(p.y * 0.047 + zz * 0.021) + 0.6 * sin(p.y * 0.113 + 0.6));")
    uv_lines.append("float2 dy = float2(3.0 * sin(zz * 0.071 + p.x * 0.037 + 2.1) + 1.8 * sin(zz * 0.17 - p.x * 0.061 + 0.4), "
                    "1.2 * sin(p.x * 0.053 + zz * 0.019 + 1.3) + 0.6 * sin(p.x * 0.101 + 2.2));")
    uv_lines.append("UV_cx = (wx + dx) / %.4f;" % CLIFF[1])
    uv_lines.append("UV_cy = (wy + dy) / %.4f;" % CLIFF[1])
    uv_lines.append("UV_cz = (p + dx * 1.7) / %.4f;" % CLIFF[1])
    uv_outputs += ["UV_cx", "UV_cy", "UV_cz"]
    for name, metres in NOISE[1]:
        uv_lines.append("UV_%s = p / %.4f;" % (name, metres))
        uv_outputs.append("UV_" + name)
    uv_code = HLSL_UV % {"body": "\n".join(uv_lines)}
    uvnode = b.custom(uv_code, [("WP", wp, "")], CMOT.CMOT_FLOAT2, [(o, CMOT.CMOT_FLOAT2) for o in uv_outputs], "TerrainUV", x=-1500, y=0)

    # ---- texture samples ------------------------------------------------------------------------------------------------------
    shade_inputs = [("WP", wp, ""), ("VN", vn, ""), ("PDepth", depth, ""), ("Wet", wet, wet_out)]
    for var, ls in layer_nodes:
        shade_inputs.append((var, ls, ""))
    row = 0

    def sample(texture_path, sampler, uv_out, var):
        nonlocal row
        row += 1
        node = b.node("TextureSample", {
            "texture": W.load(texture_path),
            "sampler_type": sampler,
            "sampler_source": unreal.SamplerSourceMode.SSM_WRAP_WORLD_GROUP_SETTINGS,
        }, x=-1250, y=row * 80)
        b.connect(uvnode, uv_out, node, "UVs")
        shade_inputs.append((var, node, "RGB"))

    for prefix, (setname, tile, kinds) in SETS.items():
        for kind in kinds:
            uv_out = ("UVF_" if kind == "f" else "UV_") + prefix
            sample(_tex_path(setname, kind), SAMPLER[kind], uv_out, "%s_%s" % (prefix, "cf" if kind == "f" else kind))
    # triplanar cliff
    cliff = CLIFF[0]
    for axis in "xyz":
        sample(_tex_path(cliff, "c"), SAMPLER["c"], "UV_c" + axis, "rc_c" + axis)
        sample(_tex_path(cliff, "n"), SAMPLER["n"], "UV_c" + axis, "rc_n" + axis)
    sample(_tex_path(cliff, "o"), SAMPLER["o"], "UV_cy", "rc_o")
    # noise (linear data)
    for name, metres in NOISE[1]:
        row += 1
        node = b.node("TextureSample", {
            "texture": W.load(NOISE[0]),
            "sampler_type": SAMPLER["d"],
            "sampler_source": unreal.SamplerSourceMode.SSM_WRAP_WORLD_GROUP_SETTINGS,
        }, x=-1250, y=row * 80)
        b.connect(uvnode, "UV_" + name, node, "UVs")
        shade_inputs.append((name, node, "RGBA"))

    shade = b.custom(HLSL_SHADE, shade_inputs, CMOT.CMOT_FLOAT4, [("Normal", CMOT.CMOT_FLOAT3), ("AO", CMOT.CMOT_FLOAT1)], "TerrainShade", x=-300, y=0)

    # ---- outputs ----------------------------------------------------------------------------------------------------------------
    rgb = b.node("ComponentMask", {"r": True, "g": True, "b": True, "a": False}, x=-100, y=0)
    b.connect(shade, "", rgb, "")
    alpha = b.node("ComponentMask", {"r": False, "g": False, "b": False, "a": True}, x=-100, y=100)
    b.connect(shade, "", alpha, "")
    mel.connect_material_property(rgb, "", MP.MP_BASE_COLOR)
    mel.connect_material_property(alpha, "", MP.MP_ROUGHNESS)
    mel.connect_material_property(shade, "Normal", MP.MP_NORMAL)
    mel.connect_material_property(shade, "AO", MP.MP_AMBIENT_OCCLUSION)

    errors = [str(e) for e in mel.recompile_material(mat)]
    W.log("MATERIAL %s nodes=%d inputs=%d compile_errors=%d %s" % (path, b.n, len(shade_inputs), len(errors), errors[:5]))
    try:
        st = mel.get_statistics(mat)
        W.log("MATERIAL_STATS pixel_instructions=%d texture_samples=%d samplers=%d vs_instructions=%d uv_scalars=%d" % (
            st.get_editor_property("num_pixel_shader_instructions"), st.get_editor_property("num_pixel_texture_samples"),
            st.get_editor_property("num_samplers"), st.get_editor_property("num_vertex_shader_instructions"), st.get_editor_property("num_uv_scalars")))
    except Exception as exc:  # noqa: BLE001
        W.warn("material statistics: %r" % (exc,))
    W.save_asset(mat)
    return errors
