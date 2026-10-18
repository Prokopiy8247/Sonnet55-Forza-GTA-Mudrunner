"""Builds the vehicle material set: masters M_Roam_Car*/..., instances MI_* named after the Blender material slots.

Substrate project (r.Substrate=True): every master ends in a Substrate front material (Slab / Simple Clear Coat / Weight for
coverage). Heavy shading lives in a few Custom HLSL nodes whose named inputs come from parameter nodes, so everything stays
overridable on instances and on the dynamic instances RoamVehicleVisuals creates.

Idempotent: masters are rebuilt (expressions wiped, instances keep their parent link), instances are re-parameterised.
Run as a job on the shared editor server:
    powershell -NoProfile -ExecutionPolicy Bypass -File Tools/ue/materials_job.ps1 Tools/ue/cars_materials.py -TimeoutSec 1500 -Filter "CARS_MAT|MATJOB|Error:"
or standalone through ue_cmd.ps1 (quits the editor at the end).  Log markers: CARS_MAT.

PARAMETER CONTRACT with Vehicle/RoamVehicleVisuals (documented in Docs/Tech/CARS_IMPORT.md):
  M_Roam_CarPaint : PrimaryColor, StripeColor (vector); StripeStyle 0..4, Metallic, BaseRoughness, ClearCoat, ClearCoatRoughness,
                    FlakeIntensity, FlakeScale, MatteFlatness, Dirt (scalars).
  Lights (M_Roam_Headlight/Taillight/Reverse/Indicator): scalar "Intensity" (0..1, can exceed 1 for bloom) times "EmissiveScale".
  M_Roam_Rim, M_Roam_Caliper: BaseColor; M_Roam_BrakeDisc: HeatGlow (0..1); M_Roam_CarGlass: TintColor, Opacity.
  Every master: Dirt, Wetness, RainIntensity, SnowAmount, DustAmount (0..1; weather MPC behind the static switch UseWorldMPC, default off).
"""
import os
import traceback

import unreal

mel = unreal.MaterialEditingLibrary
ea = unreal.EditorAssetLibrary
at = unreal.AssetToolsHelpers.get_asset_tools()
MP = unreal.MaterialProperty

JOB_MODE = "JOB_ARGS" in globals()
MAT_DIR = "/Game/Forza/Materials/Cars"
MPC_PATH = "/Game/Forza/Materials/MPC_Roam_World"
MPC_PARAMS = [("Wetness", 0.0), ("RainIntensity", 0.0), ("SnowAmount", 0.0), ("TimeOfDay", 12.0), ("DustAmount", 0.0)]


def log(msg):
    unreal.log("CARS_MAT " + str(msg))


def warn(msg):
    unreal.log_warning("CARS_MAT " + str(msg))


# ------------------------------------------------------------------------------------------------------------------
# tiny graph helper
# ------------------------------------------------------------------------------------------------------------------
class H(object):
    """Handle on one output pin."""

    def __init__(self, x, o=""):
        self.x, self.o = x, o

    def __getitem__(self, o):
        return H(self.x, o)


class Graph(object):
    def __init__(self, mat):
        self.m = mat
        self.n = 0
        self.prio = 0
        self.col = {}

    def _pos(self, depth):
        c = self.col.get(depth, 0)
        self.col[depth] = c + 1
        return -1800 + depth * 300, c * 140

    def node(self, cls, props=None, ins=None, depth=0):
        klass = getattr(unreal, "MaterialExpression" + cls)
        x, y = self._pos(depth)
        e = mel.create_material_expression(self.m, klass, x, y)
        self.n += 1
        for k, v in (props or {}).items():
            e.set_editor_property(k, v)
        for k, v in (ins or {}).items():
            self.connect(self.coerce(v), e, k)
        return H(e)

    def connect(self, src, dst_expr, name):
        if not mel.connect_material_expressions(src.x, src.o, dst_expr, name):
            raise RuntimeError("connect failed: %s[%s] -> %s.%s" % (type(src.x).__name__, src.o, type(dst_expr).__name__, name))

    def coerce(self, v):
        if isinstance(v, H):
            return v
        if isinstance(v, (int, float)):
            return self.node("Constant", {"r": float(v)})
        if isinstance(v, (tuple, list)) and len(v) == 3:
            return self.node("Constant3Vector", {"constant": unreal.LinearColor(v[0], v[1], v[2], 1.0)})
        raise TypeError(repr(v))

    def scalar(self, name, default, group="", lo=None, hi=None):
        self.prio += 1
        p = {"parameter_name": name, "default_value": float(default), "group": group, "sort_priority": self.prio}
        if lo is not None:
            p["slider_min"] = float(lo)
        if hi is not None:
            p["slider_max"] = float(hi)
        return self.node("ScalarParameter", p, depth=0)

    def vector(self, name, rgb, group=""):
        self.prio += 1
        return self.node("VectorParameter", {"parameter_name": name, "default_value": unreal.LinearColor(rgb[0], rgb[1], rgb[2], 1.0), "group": group, "sort_priority": self.prio}, depth=0)

    def mpc(self, collection, name):
        return self.node("CollectionParameter", {"collection": collection, "parameter_name": name}, depth=0)

    def custom(self, code, ins, out="float3", extra=None, desc="Custom"):
        cmot = {"float": unreal.CustomMaterialOutputType.CMOT_FLOAT1, "float2": unreal.CustomMaterialOutputType.CMOT_FLOAT2,
                "float3": unreal.CustomMaterialOutputType.CMOT_FLOAT3, "float4": unreal.CustomMaterialOutputType.CMOT_FLOAT4}
        x, y = self._pos(3)
        e = mel.create_material_expression(self.m, unreal.MaterialExpressionCustom, x, y)
        cis = []
        for name in ins:
            ci = unreal.CustomInput()
            ci.set_editor_property("input_name", name)
            cis.append(ci)
        e.set_editor_property("inputs", cis)
        e.set_editor_property("code", code)
        e.set_editor_property("output_type", cmot[out])
        e.set_editor_property("description", desc)
        if extra:
            outs = []
            for name, t in extra.items():
                co = unreal.CustomOutput()
                co.set_editor_property("output_name", name)
                co.set_editor_property("output_type", cmot[t])
                outs.append(co)
            e.set_editor_property("additional_outputs", outs)
        for name, src in ins.items():
            self.connect(self.coerce(src), e, name)
        return H(e)

    def front(self, h):
        if not mel.connect_material_property(h.x, h.o, MP.MP_FRONT_MATERIAL):
            raise RuntimeError("connect_material_property(MP_FRONT_MATERIAL) failed")


def ensure_dir(path):
    if not ea.does_directory_exist(path):
        ea.make_directory(path)


def new_material(name, **props):
    path = "%s/%s" % (MAT_DIR, name)
    ensure_dir(MAT_DIR)
    if ea.does_asset_exist(path):
        m = ea.load_asset(path)
        mel.delete_all_material_expressions(m)
    else:
        m = at.create_asset(name, MAT_DIR, unreal.Material, unreal.MaterialFactoryNew())
    m.set_editor_property("material_domain", unreal.MaterialDomain.MD_SURFACE)
    m.set_editor_property("blend_mode", unreal.BlendMode.BLEND_OPAQUE)
    m.set_editor_property("two_sided", False)
    if props.get("blend_mode", unreal.BlendMode.BLEND_OPAQUE) == unreal.BlendMode.BLEND_OPAQUE:
        m.set_editor_property("used_with_nanite", True)   # saved on the master: cooked builds cannot flip usage flags on demand
    for k, v in props.items():
        try:
            m.set_editor_property(k, v)
        except Exception as exc:  # noqa: BLE001
            warn("%s: cannot set %s: %s" % (name, k, exc))
    return m


def ensure_mpc():
    """MPC_Roam_World is owned by the world/sky agent; create a compatible one (same parameter names) only if it is missing."""
    if ea.does_asset_exist(MPC_PATH):
        mpc = ea.load_asset(MPC_PATH)
        have = [str(p.get_editor_property("parameter_name")) for p in mpc.get_editor_property("scalar_parameters")]
        missing = [n for n, _ in MPC_PARAMS if n not in have]
        if missing:
            warn("MPC_Roam_World exists but lacks %s (owned by another agent; not modified)" % missing)
        return mpc
    d, n = MPC_PATH.rsplit("/", 1)
    ensure_dir(d)
    mpc = at.create_asset(n, d, unreal.MaterialParameterCollection, unreal.MaterialParameterCollectionFactoryNew())
    params = []
    for pname, default in MPC_PARAMS:
        p = unreal.CollectionScalarParameter()
        p.set_editor_property("parameter_name", pname)
        p.set_editor_property("default_value", float(default))
        params.append(p)
    mpc.set_editor_property("scalar_parameters", params)
    ea.save_loaded_asset(mpc)
    log("created compatible %s (Wetness, RainIntensity, SnowAmount, TimeOfDay, DustAmount)" % MPC_PATH)
    return mpc


# ------------------------------------------------------------------------------------------------------------------
# shared graph fragments
# ------------------------------------------------------------------------------------------------------------------
class Env(object):
    """Geometry / weather inputs every master feeds into its Custom node."""

    def __init__(self, g, mpc):
        self.world_pos = g.node("WorldPosition")
        self.local_pos = g.node("TransformPosition", {
            "transform_source_type": unreal.MaterialPositionTransformSource.TRANSFORMPOSSOURCE_WORLD,
            "transform_type": unreal.MaterialPositionTransformSource.TRANSFORMPOSSOURCE_LOCAL}, {"": self.world_pos}, depth=1)
        self.world_n = g.node("PixelNormalWS")
        self.local_n = g.node("Transform", {
            "transform_source_type": unreal.MaterialVectorCoordTransformSource.TRANSFORMSOURCE_WORLD,
            "transform_type": unreal.MaterialVectorCoordTransform.TRANSFORM_LOCAL}, {"": self.world_n}, depth=1)
        self.cam_pos = g.node("CameraPositionWS")
        # Weather: per-instance scalars by default. MaterialParameterCollection nodes reference the collection's parameters by GUID, which
        # change whenever the owner of MPC_Roam_World rebuilds its parameter list (the saved master then fails to compile at load:
        # "CollectionParameter has invalid parameter None"). So the MPC is behind the static switch UseWorldMPC (default off; only the
        # active branch is compiled) and must be re-linked by re-running this script after the MPC has changed.
        self.wet = self.weather(g, mpc, "Wetness", 0.0)
        self.rain = self.weather(g, mpc, "RainIntensity", 0.0)
        self.snow = self.weather(g, mpc, "SnowAmount", 0.0)
        self.dust = self.weather(g, mpc, "DustAmount", 0.0)


def _weather(self, g, mpc, name, default):
    g.prio += 1
    return g.node("StaticSwitchParameter", {"parameter_name": "UseWorldMPC", "default_value": False, "group": "Weather", "sort_priority": 900},
                  {"True": g.mpc(mpc, name), "False": g.scalar(name, default, "Weather", 0, 1)}, depth=1)


Env.weather = _weather

ENV_INPUTS = ["LocalPos", "LocalN", "WorldPos", "WorldN", "CamPos", "Wetness", "Rain", "Snow", "Dust"]


def env_ins(env):
    return {"LocalPos": env.local_pos, "LocalN": env.local_n, "WorldPos": env.world_pos, "WorldN": env.world_n, "CamPos": env.cam_pos,
            "Wetness": env.wet, "Rain": env.rain, "Snow": env.snow, "Dust": env.dust}


HASH_FUNC_NOTE = "// hash: Dave Hoskins style, stable at large coordinates"

# ---- car paint ----------------------------------------------------------------------------------------------------
PAINT_CODE = r"""
float3 pos = LocalPos;
float3 n = normalize(LocalN);
float ay = abs(pos.y);
float top = smoothstep(0.35, 0.75, n.z);
float side = smoothstep(0.55, 0.85, abs(n.y));
float s = floor(StripeStyle + 0.5);
float w = 0.0;
if (s == 1.0) { w = top * smoothstep(8.0, 8.8, ay) * (1.0 - smoothstep(19.2, 20.0, ay)); }
else if (s == 2.0) { w = top * (1.0 - smoothstep(17.2, 18.0, ay)); }
else if (s == 3.0) { w = top * ((1.0 - smoothstep(11.2, 12.0, ay)) + smoothstep(15.0, 15.8, ay) * (1.0 - smoothstep(17.2, 18.0, ay))); }
else if (s == 4.0) { w = side * smoothstep(40.0, 40.8, pos.z) * (1.0 - smoothstep(49.2, 50.0, pos.z)); }
w = saturate(w);
float3 base = lerp(PrimaryColor, StripeColor, w);

// dirt: low parts dirtier, blotchy; plus global dust from the weather collection
float low = saturate(1.0 - pos.z / 110.0);
float dirtAmt = saturate((Dirt * (0.35 + 0.9 * low) + Dust * 0.35 * (0.4 + 0.6 * low)) * (0.55 + 0.9 * NoiseA));
base = lerp(base, float3(0.27, 0.21, 0.15), dirtAmt * 0.88);
// snow on up-facing surfaces
float snowAmt = saturate(Snow * smoothstep(0.5, 0.85, WorldN.z) * (0.7 + 0.6 * NoiseA));
base = lerp(base, float3(0.82, 0.85, 0.90), snowAmt);
// wet film darkens and smooths
base *= lerp(1.0, 0.86, saturate(Wetness) * (1.0 - dirtAmt));

// metallic flakes: random tilted micro-facets in 3D cells of the local position, faded with distance
float cellSize = 100.0 / max(FlakeScale, 1.0);
float3 c = floor(pos / cellSize);
float3 p3 = frac(c * float3(0.1031, 0.1030, 0.0973));
p3 += dot(p3, p3.yxz + 33.33);
float3 h = frac((p3.xxy + p3.yxx) * p3.zyx);
float fade = (1.0 - smoothstep(250.0, 1300.0, length(WorldPos - CamPos))) * FlakeIntensity;
float2 tilt = (h.xy - 0.5) * 2.0;
FlakeN = normalize(float3(tilt * 0.6 * fade, 1.0));
float sparkle = step(0.80, h.z) * fade;
base *= 1.0 + fade * (h.z - 0.5) * 0.45 + sparkle * 0.35;

float mf = saturate(MatteFlatness);
float rough = lerp(BaseRoughness, 0.88, mf);
rough = lerp(rough, rough * 0.72, saturate(Wetness) * (1.0 - dirtAmt) * (1.0 - mf));
rough = lerp(rough, 0.9, dirtAmt * 0.8);
rough = lerp(rough, rough * 0.55, sparkle);
Rough = saturate(rough);
Metal = saturate(Metallic) * (1.0 - dirtAmt * 0.6);
CCCov = saturate(ClearCoat * (1.0 - mf) * (1.0 - dirtAmt * 0.9));
CCRough = saturate(ClearCoatRoughness + dirtAmt * 0.3);
return base;
"""


def build_paint(mpc):
    m = new_material("M_Roam_CarPaint")
    g = Graph(m)
    env = Env(g, mpc)
    ins = {
        "PrimaryColor": g.vector("PrimaryColor", (0.65, 0.04, 0.04), "Paint"),
        "StripeColor": g.vector("StripeColor", (0.02, 0.02, 0.02), "Paint"),
        "StripeStyle": g.scalar("StripeStyle", 0, "Paint", 0, 4),
        "Metallic": g.scalar("Metallic", 0.0, "Finish", 0, 1),
        "BaseRoughness": g.scalar("BaseRoughness", 0.38, "Finish", 0, 1),
        "ClearCoat": g.scalar("ClearCoat", 1.0, "Finish", 0, 1),
        "ClearCoatRoughness": g.scalar("ClearCoatRoughness", 0.035, "Finish", 0, 1),
        "FlakeIntensity": g.scalar("FlakeIntensity", 0.0, "Finish", 0, 1),
        "FlakeScale": g.scalar("FlakeScale", 700.0, "Finish", 50, 3000),
        "MatteFlatness": g.scalar("MatteFlatness", 0.0, "Finish", 0, 1),
        "Dirt": g.scalar("Dirt", 0.0, "Weathering", 0, 1),
        "NoiseA": g.node("Noise", {"scale": 0.045, "quality": 1, "levels": 3, "output_min": 0.0, "output_max": 1.0, "level_scale": 2.0, "turbulence": False}, {"World Position": env.local_pos}, depth=2),
    }
    ins.update(env_ins(env))
    extra = {"Metal": "float", "Rough": "float", "CCCov": "float", "CCRough": "float", "FlakeN": "float3"}
    c = g.custom(PAINT_CODE, ins, out="float3", extra=extra, desc="CarPaint")
    conv = g.node("SubstrateMetalnessToDiffuseAlbedoF0", None, {"BaseColor": c, "Metallic": c["Metal"], "Specular": 0.5}, depth=4)
    coat = g.node("SubstrateSimpleClearCoatBSDF", None, {
        "Diffuse Albedo": conv["DiffuseAlbedo"], "F0": conv["F0"], "Roughness": c["Rough"],
        "Clear Coat Coverage": c["CCCov"], "Clear Coat Roughness": c["CCRough"], "Bottom Normal": c["FlakeN"]}, depth=5)
    g.front(coat)
    return finish(m, g)


# ---- generic surface (plastic / rubber / metal / tyre / brake disc / plate / fabric / rust / wood) ----------------------
SURFACE_CODE = r"""
float3 pos = LocalPos;
float3 base = BaseColor;
float rough = Roughness;
float metal = Metallic;
float fuzz = FuzzAmount;
float3 emis = float3(0.0, 0.0, 0.0);
float grain = 0.0;
float dirtLevel = saturate(Dirt + Dust * 0.25);
#if KIND == 1
  // tyre: wheel axle along local Y -> radius in the XZ plane. Tread band is the outer radius, sidewall the inner.
  float rr = length(pos.xz);
  float tread = smoothstep(0.80, 0.92, saturate(abs(pos.y) / max(TyreHalfWidth, 1.0)));
  float shoulder = 1.0 - tread;
  grain = NoiseA * 0.8 + 0.2;
  rough = lerp(0.78, 0.93, tread) + (NoiseA - 0.5) * 0.08;
  base *= lerp(1.0, 1.12, NoiseA * tread);
  dirtLevel *= (0.5 + 0.8 * saturate(1.0 - pos.z / 40.0));
#elif KIND == 2
  // brake disc: friction ring lighter/brighter metal, hat darker, rust near the edge, heat glow
  float rr = length(pos.xz);
  float ring = smoothstep(DiscInner, DiscInner + 1.5, rr);
  float rust = saturate((NoiseA - 0.45) * 1.4) * 0.14;
  float brush = 0.5 + 0.5 * sin(rr * 5.0);   // fine concentric machining marks
  base = lerp(float3(0.05, 0.05, 0.055), lerp(BaseColor * (0.9 + 0.1 * brush), float3(0.28, 0.14, 0.07), rust), ring);
  rough = lerp(0.55, 0.36 + rust * 0.3 + 0.06 * brush, ring);
  metal = lerp(0.6, 0.95, ring);
  emis = float3(1.0, 0.28, 0.04) * (HeatGlow * HeatGlow * 6.0) * ring;
  grain = NoiseA * 0.2;
#elif KIND == 3
  // number plate: off-white with dark border and a faint embossed band (no characters)
  float2 uvp = float2(pos.y, pos.z);
  base = BaseColor * (0.92 + 0.08 * NoiseA);
  rough = 0.42;
#elif KIND == 4
  // fabric / carpet: fuzzy, noisy weave brightness
  grain = NoiseA;
  base *= 0.82 + 0.36 * NoiseA;
#elif KIND == 5
  // rust: orange-brown blotches
  base = lerp(BaseColor, BaseColor * float3(0.55, 0.38, 0.30), NoiseA);
  rough = 0.78 + 0.18 * NoiseA;
  grain = NoiseA * 0.5;
#elif KIND == 6
  // wood planks: stripes along local X with random shade per plank
  float plank = floor((pos.y + 2000.0) / 12.0);
  float ph = frac(sin(plank * 12.9898) * 43758.5453);
  base = BaseColor * (0.7 + 0.5 * ph) * (0.85 + 0.3 * NoiseA);
  rough = 0.72;
  grain = NoiseA * 0.4;
#elif KIND == 7
  // brushed metal (trim)
  grain = NoiseA * 0.3;
  rough = Roughness + (NoiseA - 0.5) * 0.12;
#else
  grain = NoiseA * 0.5 + 0.25;
#endif
// weathering common to all
base = lerp(base, float3(0.27, 0.21, 0.15), dirtLevel * 0.5 * (0.5 + NoiseA));
rough = lerp(rough, 0.92, dirtLevel * 0.3);
base *= lerp(1.0, 0.88, saturate(Wetness) * 0.7);
rough = lerp(rough, rough * 0.75, saturate(Wetness) * 0.6);
Rough = saturate(rough);
Metal = saturate(metal);
Fuzz = saturate(fuzz);
Emis = emis;
// smooth tangent-space bump: two decorrelated noise fields tilt the normal
float2 tilt = (float2(NoiseA, NoiseB) - 0.5) * GrainStrength * (0.4 + grain);
Nrm = normalize(float3(tilt, 1.0));
return base;
"""

SURFACE_KINDS = {"plain": 0, "tyre": 1, "disc": 2, "plate": 3, "fabric": 4, "rust": 5, "wood": 6, "brushed": 7}


def build_surface(name, kind, defaults, extra_scalars=None, extra_vectors=None):
    """One Slab master. `defaults` = dict BaseColor(rgb) Metallic Roughness Specular Fuzz GrainStrength ..."""
    m = new_material(name)
    g = Graph(m)
    mpc = ea.load_asset(MPC_PATH)
    env = Env(g, mpc)
    d = defaults
    ins = {
        "BaseColor": g.vector("BaseColor", d.get("BaseColor", (0.5, 0.5, 0.5)), "Surface"),
        "Metallic": g.scalar("Metallic", d.get("Metallic", 0.0), "Surface", 0, 1),
        "Roughness": g.scalar("Roughness", d.get("Roughness", 0.5), "Surface", 0, 1),
        "Specular": g.scalar("Specular", d.get("Specular", 0.5), "Surface", 0, 1),
        "FuzzAmount": g.scalar("FuzzAmount", d.get("Fuzz", 0.0), "Surface", 0, 1),
        "GrainStrength": g.scalar("GrainStrength", d.get("Grain", 0.15), "Surface", 0, 1),
        "Dirt": g.scalar("Dirt", 0.0, "Weathering", 0, 1),
        "NoiseA": g.node("Noise", {"scale": d.get("NoiseScale", 0.25), "quality": 1, "levels": 3, "output_min": 0.0, "output_max": 1.0, "level_scale": 2.0, "turbulence": False}, {"World Position": env.local_pos}, depth=2),
        "NoiseB": g.node("Noise", {"scale": d.get("NoiseScale", 0.25), "quality": 1, "levels": 3, "output_min": 0.0, "output_max": 1.0, "level_scale": 2.0, "turbulence": False},
                         {"World Position": g.node("Add", None, {"A": env.local_pos, "B": (37.0, 91.0, 13.0)}, depth=2)}, depth=3),
    }
    for k, v in (extra_scalars or {}).items():
        ins[k] = g.scalar(k, v[0], "Surface", *v[1:])
    for k, v in (extra_vectors or {}).items():
        ins[k] = g.vector(k, v, "Surface")
    for k in ("TyreHalfWidth", "DiscInner", "HeatGlow"):
        if k not in ins:
            ins[k] = g.scalar(k, {"TyreHalfWidth": 10.0, "DiscInner": 9.0, "HeatGlow": 0.0}[k], "Surface")
    ins.update(env_ins(env))
    code = "#define KIND %d\n%s" % (SURFACE_KINDS[kind], SURFACE_CODE)
    c = g.custom(code, ins, out="float3", extra={"Rough": "float", "Metal": "float", "Fuzz": "float", "Emis": "float3", "Nrm": "float3"}, desc=name)
    conv = g.node("SubstrateMetalnessToDiffuseAlbedoF0", None, {"BaseColor": c, "Metallic": c["Metal"], "Specular": ins["Specular"]}, depth=4)
    slab = g.node("SubstrateSlabBSDF", None, {
        "Diffuse Albedo": conv["DiffuseAlbedo"], "F0": conv["F0"], "F90": (1.0, 1.0, 1.0), "Roughness": c["Rough"], "Normal": c["Nrm"],
        "Emissive Color": c["Emis"], "Fuzz Amount": c["Fuzz"], "Fuzz Color": ins["BaseColor"], "Fuzz Roughness": 0.6}, depth=5)
    g.front(slab)
    return finish(m, g)


# ---- lights --------------------------------------------------------------------------------------------------------------
LIGHT_CODE = r"""
// lens: glossy coloured plastic; emissive part = EmissiveColor * Intensity * EmissiveScale (+ small idle glow of the lamp body)
float i = max(Intensity, 0.0);
float3 lens = LensColor;
// bright core of the lamp: stronger at the centre of the lens, i.e. when looking straight at it
float f = saturate(dot(normalize(WorldN), normalize(CamPos - WorldPos)));
float core = 0.65 + 0.35 * pow(f, 1.5);
Emis = EmissiveColor * (i * EmissiveScale * core + IdleGlow);
Rough = lerp(0.07, 0.35, saturate(Dirt + Dust * 0.2));
return lens;
"""


def build_light(name, emissive, lens, scale, idle_glow):
    m = new_material(name)
    g = Graph(m)
    mpc = ea.load_asset(MPC_PATH)
    env = Env(g, mpc)
    ins = {
        "EmissiveColor": g.vector("EmissiveColor", emissive, "Light"),
        "LensColor": g.vector("LensColor", lens, "Light"),
        "Intensity": g.scalar("Intensity", 0.0, "Light", 0, 4),
        "EmissiveScale": g.scalar("EmissiveScale", scale, "Light", 0, 200),
        "IdleGlow": g.scalar("IdleGlow", idle_glow, "Light", 0, 5),
        "Dirt": g.scalar("Dirt", 0.0, "Weathering", 0, 1),
        "WorldN": env.world_n, "WorldPos": env.world_pos, "CamPos": env.cam_pos, "Dust": env.dust,
    }
    c = g.custom(LIGHT_CODE, ins, out="float3", extra={"Emis": "float3", "Rough": "float"}, desc=name)
    slab = g.node("SubstrateSlabBSDF", None, {
        "Diffuse Albedo": c, "F0": (0.045, 0.045, 0.045), "F90": (1.0, 1.0, 1.0), "Roughness": c["Rough"], "Emissive Color": c["Emis"]}, depth=5)
    g.front(slab)
    return finish(m, g)


# ---- glass ---------------------------------------------------------------------------------------------------------------
GLASS_CODE = r"""
float3 n = normalize(WorldN);
float3 v = normalize(CamPos - WorldPos);
float fres = pow(1.0 - saturate(abs(dot(n, v))), max(FresnelPower, 0.5));
float haze = saturate(Dirt + Dust * 0.3 + (1.0 - saturate(abs(dot(n, v)))) * 0.0);
// rain droplets: random cells on the local surface; each droplet is more opaque and rougher
float rainAmt = saturate(Rain) * RainStrength;
float cellSize = 3.2;
float3 c = floor(LocalPos / cellSize);
float3 p3 = frac(c * float3(0.1031, 0.1030, 0.0973));
p3 += dot(p3, p3.yxz + 33.33);
float3 h = frac((p3.xxy + p3.yxx) * p3.zyx);
float3 lp = frac(LocalPos / cellSize) - 0.5;
float d = length(lp) * 2.0;
float drop = step(h.x, rainAmt * 0.55) * (1.0 - smoothstep(0.25 + h.y * 0.35, 0.55 + h.y * 0.35, d));
float cover = Opacity + (1.0 - Opacity) * fres * 0.85;
cover = saturate(max(cover, haze * 0.55) + drop * 0.35);
Cover = cover;
Rough = saturate(lerp(0.025, 0.35, saturate(haze * 0.8 + drop)));
return lerp(TintColor, float3(0.06, 0.055, 0.05), saturate(haze * 0.6));
"""


def build_glass():
    m = new_material("M_Roam_CarGlass", blend_mode=unreal.BlendMode.BLEND_TRANSLUCENT, two_sided=True)
    for prop, val in (("translucency_lighting_mode", unreal.TranslucencyLightingMode.TLM_SURFACE_PER_PIXEL_LIGHTING),):
        try:
            m.set_editor_property(prop, val)
        except Exception as exc:  # noqa: BLE001
            warn("glass: %s: %s" % (prop, exc))
    g = Graph(m)
    mpc = ea.load_asset(MPC_PATH)
    env = Env(g, mpc)
    ins = {
        "TintColor": g.vector("TintColor", (0.012, 0.018, 0.02), "Glass"),
        "Opacity": g.scalar("Opacity", 0.22, "Glass", 0, 1),
        "FresnelPower": g.scalar("FresnelPower", 3.0, "Glass", 0.5, 8),
        "RainStrength": g.scalar("RainStrength", 1.0, "Glass", 0, 1),
        "Dirt": g.scalar("Dirt", 0.0, "Weathering", 0, 1),
        "LocalPos": env.local_pos, "WorldN": env.world_n, "WorldPos": env.world_pos, "CamPos": env.cam_pos, "Rain": env.rain, "Dust": env.dust,
    }
    c = g.custom(GLASS_CODE, ins, out="float3", extra={"Cover": "float", "Rough": "float"}, desc="Glass")
    slab = g.node("SubstrateSlabBSDF", None, {"Diffuse Albedo": c, "F0": (0.045, 0.045, 0.045), "F90": (1.0, 1.0, 1.0), "Roughness": c["Rough"]}, depth=5)
    weighted = g.node("SubstrateWeight", None, {"A": slab, "Weight": c["Cover"]}, depth=6)
    g.front(weighted)
    return finish(m, g)


def finish(m, g):
    errs = [str(e) for e in mel.recompile_material(m)]
    ea.save_loaded_asset(m)
    status = "OK" if not errs else "ERRORS"
    log("master %s nodes=%d %s %s" % (m.get_name(), g.n, status, ("\n".join(errs))[:1500] if errs else ""))
    return m


# ------------------------------------------------------------------------------------------------------------------
# instances
# ------------------------------------------------------------------------------------------------------------------
def new_instance(name, parent, scalars=None, vectors=None):
    path = "%s/%s" % (MAT_DIR, name)
    if ea.does_asset_exist(path):
        mi = ea.load_asset(path)
    else:
        mi = at.create_asset(name, MAT_DIR, unreal.MaterialInstanceConstant, unreal.MaterialInstanceConstantFactoryNew())
    mel.set_material_instance_parent(mi, parent)
    mi.set_editor_property("scalar_parameter_values", [])
    mi.set_editor_property("vector_parameter_values", [])
    # NOTE: MaterialEditingLibrary.set_material_instance_*_parameter_value always RETURNS False in 5.8.2 (bResult is never set,
    # engine source MaterialEditingLibrary.cpp:1485) although the value is applied -> verify by reading the value back.
    for k, v in (scalars or {}).items():
        mel.set_material_instance_scalar_parameter_value(mi, k, float(v))
        got = mel.get_material_instance_scalar_parameter_value(mi, k)
        if abs(got - float(v)) > 1e-4:
            warn("%s: scalar %s not applied (read back %s, wanted %s; missing in parent %s?)" % (name, k, got, v, parent.get_name()))
    for k, v in (vectors or {}).items():
        v = tuple(v) + (1.0,) if len(v) == 3 else tuple(v)
        mel.set_material_instance_vector_parameter_value(mi, k, unreal.LinearColor(*v))
        got = mel.get_material_instance_vector_parameter_value(mi, k)
        if abs(got.r - v[0]) > 1e-3 or abs(got.g - v[1]) > 1e-3 or abs(got.b - v[2]) > 1e-3:
            warn("%s: vector %s not applied (read back %s, wanted %s)" % (name, k, got, v))
    mel.update_material_instance(mi)
    ea.save_loaded_asset(mi)
    return mi


def srgb(hex_color):
    h = hex_color.lstrip("#")
    out = []
    for i in (0, 2, 4):
        c = int(h[i:i + 2], 16) / 255.0
        out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    return tuple(out)


def main():
    ensure_dir(MAT_DIR)
    if ea.does_directory_exist(MAT_DIR + "/_Probe"):
        ea.delete_directory(MAT_DIR + "/_Probe")      # scratch assets of the API probes
    mpc = ensure_mpc()
    masters = {}
    masters["paint"] = build_paint(mpc)
    masters["glass"] = build_glass()
    P = {  # master name -> (kind, defaults, extra scalars, extra vectors)
        "M_Roam_Chrome": ("plain", dict(BaseColor=(0.90, 0.91, 0.93), Metallic=1.0, Roughness=0.07, Grain=0.0), None, None),
        "M_Roam_TrimBlack": ("plain", dict(BaseColor=(0.022, 0.022, 0.024), Roughness=0.52, Grain=0.14, NoiseScale=0.5), None, None),
        "M_Roam_Rubber": ("plain", dict(BaseColor=(0.012, 0.012, 0.013), Roughness=0.9, Grain=0.10, NoiseScale=0.4), None, None),
        "M_Roam_Tyre": ("tyre", dict(BaseColor=(0.016, 0.016, 0.017), Roughness=0.85, Grain=0.12, NoiseScale=0.6), {"TyreHalfWidth": (10.0, 1.0, 40.0)}, None),
        "M_Roam_Rim": ("plain", dict(BaseColor=(0.78, 0.79, 0.82), Metallic=1.0, Roughness=0.22, Grain=0.0), None, None),
        "M_Roam_BrakeDisc": ("disc", dict(BaseColor=(0.45, 0.45, 0.47), Metallic=0.9, Roughness=0.4, Grain=0.05, NoiseScale=0.12), {"DiscInner": (9.0, 1.0, 40.0), "HeatGlow": (0.0, 0.0, 1.0)}, None),
        "M_Roam_Caliper": ("plain", dict(BaseColor=(0.55, 0.02, 0.02), Roughness=0.3, Specular=0.55, Grain=0.0), None, None),
        "M_Roam_Plate": ("plate", dict(BaseColor=(0.85, 0.84, 0.78), Roughness=0.42, Grain=0.0, NoiseScale=0.6), None, None),
        "M_Roam_Exhaust": ("brushed", dict(BaseColor=(0.36, 0.34, 0.31), Metallic=0.95, Roughness=0.34, Grain=0.1, NoiseScale=0.8), None, None),
        "M_Roam_IntDash": ("plain", dict(BaseColor=(0.035, 0.035, 0.04), Roughness=0.62, Grain=0.16, NoiseScale=0.5), None, None),
        "M_Roam_IntSeat": ("fabric", dict(BaseColor=(0.08, 0.075, 0.07), Roughness=0.6, Fuzz=0.35, Grain=0.12, NoiseScale=0.8), None, None),
        "M_Roam_IntTrim": ("brushed", dict(BaseColor=(0.55, 0.56, 0.58), Metallic=0.9, Roughness=0.35, Grain=0.1, NoiseScale=1.0), None, None),
        "M_Roam_IntCarpet": ("fabric", dict(BaseColor=(0.05, 0.05, 0.055), Roughness=0.95, Fuzz=0.8, Grain=0.18, NoiseScale=1.0), None, None),
        "M_Roam_Rust": ("rust", dict(BaseColor=(0.32, 0.13, 0.06), Metallic=0.4, Roughness=0.8, Grain=0.5, NoiseScale=0.35), None, None),
        "M_Roam_Wood": ("wood", dict(BaseColor=(0.30, 0.19, 0.10), Roughness=0.72, Grain=0.4, NoiseScale=0.6), None, None),
    }
    for name, (kind, d, es, ev) in P.items():
        masters[name] = build_surface(name, kind, d, es, ev)
    masters["headlight"] = build_light("M_Roam_Headlight", (1.0, 0.90, 0.72), (0.06, 0.06, 0.065), 28.0, 0.0)
    masters["taillight"] = build_light("M_Roam_Taillight", (1.0, 0.008, 0.004), (0.22, 0.008, 0.01), 6.0, 0.0)
    masters["reverse"] = build_light("M_Roam_Reverse", (0.92, 0.95, 1.0), (0.55, 0.55, 0.58), 22.0, 0.0)
    masters["indicator"] = build_light("M_Roam_Indicator", (1.0, 0.42, 0.02), (0.30, 0.10, 0.01), 22.0, 0.0)

    # ---- instances named after the Blender material slots -------------------------------------------------------------
    def inst(slot, master, scalars=None, vectors=None):
        mi = new_instance("MI_" + slot, masters[master] if master in masters else ea.load_asset("%s/%s" % (MAT_DIR, master)), scalars, vectors)
        log("instance MI_%s -> %s" % (slot, master))
        return mi

    # Paint: gloss defaults; the visuals component overrides colour/finish at runtime
    inst("Paint", "paint", dict(Metallic=0.0, BaseRoughness=0.38, ClearCoat=1.0, ClearCoatRoughness=0.035, FlakeIntensity=0.0, MatteFlatness=0.0, StripeStyle=0.0),
         dict(PrimaryColor=srgb("#c8202a"), StripeColor=srgb("#1a1a1c")))
    inst("Paint2", "paint", dict(Metallic=0.0, BaseRoughness=0.40, ClearCoat=1.0, ClearCoatRoughness=0.04, FlakeIntensity=0.0, MatteFlatness=0.0, StripeStyle=0.0),
         dict(PrimaryColor=srgb("#1a1a1c"), StripeColor=srgb("#1a1a1c")))
    inst("Glass", "glass", dict(Opacity=0.22, FresnelPower=3.0), dict(TintColor=(0.012, 0.018, 0.02)))
    inst("Chrome", "M_Roam_Chrome")
    inst("TrimBlack", "M_Roam_TrimBlack")
    inst("TrimGrey", "M_Roam_TrimBlack", dict(Roughness=0.5, GrainStrength=0.12), dict(BaseColor=srgb("#6f7378")))
    inst("Rubber", "M_Roam_Rubber")
    inst("Tyre", "M_Roam_Tyre")
    inst("Rim", "M_Roam_Rim", None, dict(BaseColor=srgb("#c7cad0")))
    inst("RimDark", "M_Roam_Rim", dict(Roughness=0.38, Metallic=0.8), dict(BaseColor=srgb("#2c2e33")))
    inst("BrakeDisc", "M_Roam_BrakeDisc")
    inst("Caliper", "M_Roam_Caliper", None, dict(BaseColor=srgb("#b3141c")))
    inst("Plate", "M_Roam_Plate")
    inst("Underbody", "M_Roam_TrimBlack", dict(Roughness=0.88, GrainStrength=0.25), dict(BaseColor=srgb("#171719")))
    inst("Exhaust", "M_Roam_Exhaust")
    inst("IntDash", "M_Roam_IntDash")
    inst("IntSeat", "M_Roam_IntSeat", None, dict(BaseColor=srgb("#2a2623")))
    inst("IntTrim", "M_Roam_IntTrim")
    inst("IntCarpet", "M_Roam_IntCarpet")
    inst("Headlight", "headlight")
    inst("Taillight", "taillight")
    inst("Reverse", "reverse")
    inst("Indicator", "indicator")
    inst("Traffic_Rust", "M_Roam_Rust")
    inst("Traffic_Wood", "M_Roam_Wood")
    log("done: %d masters" % len(masters))


try:
    main()
except Exception:  # noqa: BLE001
    traceback.print_exc()
    unreal.log_error("CARS_MAT FAILED")
finally:
    if not JOB_MODE:
        unreal.SystemLibrary.execute_console_command(None, "QUIT_EDITOR")
