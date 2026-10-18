"""world_water - the sea at z = 0.   Docs/Tech/WORLD_BUILD.md

Default: a huge static plane with M_Roam_Sea (Single Layer Water shading: depth-based absorption/scattering, two scrolling normal maps,
Lumen reflections) - cheap, robust headless, and the heightmap already contains the sea floor (Sand layer) so the shore gradient comes
from the water depth.  Option ROAM_WORLD_OCEAN=plugin tries the Water plugin (WaterZone + WaterBodyOcean) instead (experimental plugin).
"""
import unreal

import world_lib as W

mel = unreal.MaterialEditingLibrary
MP = unreal.MaterialProperty
CMOT = unreal.CustomMaterialOutputType

SEA_MAT = W.LANDSCAPE_MAT_DIR + "/M_Roam_Sea"
PLANE_HALF_EXTENT_CM = 3000000.0     # 30 km each way: the sea reaches the horizon from the coast and from the mountains

def _build_material():
    d, n = SEA_MAT.rsplit("/", 1)
    W.ensure_dir(d)
    if W.ea.does_asset_exist(SEA_MAT):
        mat = W.load(SEA_MAT)
        mel.delete_all_material_expressions(mat)
    else:
        mat = W.tools.create_asset(n, d, unreal.Material, unreal.MaterialFactoryNew())
    mat.set_editor_property("material_domain", unreal.MaterialDomain.MD_SURFACE)
    mat.set_editor_property("blend_mode", unreal.BlendMode.BLEND_OPAQUE)
    mat.set_editor_property("shading_model", unreal.MaterialShadingModel.MSM_SINGLE_LAYER_WATER)
    mat.set_editor_property("two_sided", False)

    def node(cls, props=None, x=-900, y=0):
        e = mel.create_material_expression(mat, getattr(unreal, "MaterialExpression" + cls), x, y)
        for k, v in (props or {}).items():
            e.set_editor_property(k, v)
        return e

    def link(src, src_out, dst, dst_in):
        if not mel.connect_material_expressions(src, src_out, dst, dst_in):
            raise RuntimeError("connect failed %s[%s] -> %s.%s" % (type(src).__name__, src_out, type(dst).__name__, dst_in))

    wp = node("WorldPosition", y=0)
    t = node("Time", y=100)
    # UV generator (custom, two outputs)
    uvc = mel.create_material_expression(mat, unreal.MaterialExpressionCustom, -700, 0)
    for prop, value in (("code", "float2 p = WP.xy * 0.01;\nUV_B = p / 11.0 + float2(-0.017, 0.029) * T;\nUV_A = p / 38.0 + float2(0.021, 0.013) * T;\nreturn p;"),
                        ("output_type", CMOT.CMOT_FLOAT2), ("description", "SeaUV")):
        uvc.set_editor_property(prop, value)
    ins = []
    for name in ("WP", "T"):
        ci = unreal.CustomInput()
        ci.set_editor_property("input_name", name)
        ins.append(ci)
    uvc.set_editor_property("inputs", ins)
    outs = []
    for name in ("UV_A", "UV_B"):
        co = unreal.CustomOutput()
        co.set_editor_property("output_name", name)
        co.set_editor_property("output_type", CMOT.CMOT_FLOAT2)
        outs.append(co)
    uvc.set_editor_property("additional_outputs", outs)
    link(wp, "", uvc, "WP")
    link(t, "", uvc, "T")

    samples = []
    for i, (tex_name, uv_out) in enumerate((("T_water_normal_a_N", "UV_A"), ("T_water_normal_b_N", "UV_B"))):
        s = node("TextureSample", {
            "texture": W.load("%s/FX/%s" % (W.TEX_ROOT, tex_name)),
            "sampler_type": unreal.MaterialSamplerType.SAMPLERTYPE_NORMAL,
            "sampler_source": unreal.SamplerSourceMode.SSM_WRAP_WORLD_GROUP_SETTINGS,
        }, x=-500, y=i * 120)
        link(uvc, uv_out, s, "UVs")
        samples.append(s)

    blend = mel.create_material_expression(mat, unreal.MaterialExpressionCustom, -250, 0)
    blend.set_editor_property("code", "float3 a = nA; float3 b = nB;\nfloat k = lerp(1.0, 0.25, saturate((PDepth * 0.01 - 150.0) / 2500.0));\nfloat3 n = float3((a.xy + b.xy) * 0.9 * k, a.z * b.z);\nreturn normalize(n);")
    blend.set_editor_property("output_type", CMOT.CMOT_FLOAT3)
    blend.set_editor_property("description", "SeaNormal")
    ins = []
    for name in ("nA", "nB", "PDepth"):
        ci = unreal.CustomInput()
        ci.set_editor_property("input_name", name)
        ins.append(ci)
    blend.set_editor_property("inputs", ins)
    depth = node("PixelDepth", y=300)
    link(samples[0], "RGB", blend, "nA")
    link(samples[1], "RGB", blend, "nB")
    link(depth, "", blend, "PDepth")

    # single layer water: coefficients are per centimetre. Absorption removes red first (blue-green water), scattering gives the milky turquoise
    scattering = node("Constant3Vector", {"constant": unreal.LinearColor(0.0015, 0.0042, 0.0058, 1.0)}, y=420)
    absorption = node("Constant3Vector", {"constant": unreal.LinearColor(0.0085, 0.0026, 0.0014, 1.0)}, y=520)
    phase = node("Constant", {"r": 0.35}, y=620)
    water_out = node("SingleLayerWaterMaterialOutput", x=-100, y=420)
    link(scattering, "", water_out, "ScatteringCoefficients")
    link(absorption, "", water_out, "AbsorptionCoefficients")
    link(phase, "", water_out, "PhaseG")

    base = node("Constant3Vector", {"constant": unreal.LinearColor(0.0, 0.0, 0.0, 1.0)}, y=720)   # water colour comes from the volume terms
    rough = node("Constant", {"r": 0.07}, y=800)
    opacity = node("Constant", {"r": 1.0}, y=880)
    spec = node("Constant", {"r": 0.5}, y=960)
    mel.connect_material_property(base, "", MP.MP_BASE_COLOR)
    mel.connect_material_property(rough, "", MP.MP_ROUGHNESS)
    mel.connect_material_property(spec, "", MP.MP_SPECULAR)
    mel.connect_material_property(opacity, "", MP.MP_OPACITY)
    mel.connect_material_property(blend, "", MP.MP_NORMAL)
    errors = [str(e) for e in mel.recompile_material(mat)]
    W.log("SEA_MATERIAL %s compile_errors=%d %s" % (SEA_MAT, len(errors), errors[:5]))
    W.save_asset(mat)
    return mat


def _plane(mat):
    mesh = W.load("/Engine/BasicShapes/Plane.Plane")      # 100 x 100 uu, normal +Z
    actor = W.actors.spawn_actor_from_class(unreal.StaticMeshActor, unreal.Vector(0.0, 0.0, 0.0), unreal.Rotator(0.0, 0.0, 0.0))
    actor.set_actor_label("Sea")
    actor.set_folder_path("Roam/Water")
    actor.set_actor_scale3d(unreal.Vector(PLANE_HALF_EXTENT_CM * 2.0 / 100.0, PLANE_HALF_EXTENT_CM * 2.0 / 100.0, 1.0))
    c = actor.static_mesh_component
    c.set_static_mesh(mesh)
    c.set_material(0, mat)
    c.set_mobility(unreal.ComponentMobility.STATIC)
    c.set_collision_enabled(unreal.CollisionEnabled.NO_COLLISION)
    c.set_cast_shadow(False)
    try:
        actor.set_editor_property("is_spatially_loaded", False)
    except Exception:  # noqa: BLE001
        pass
    W.log("SEA_PLANE spawned half extent %.0f m" % (PLANE_HALF_EXTENT_CM / 100.0))
    return actor


def _plugin_ocean():
    zone = W.actors.spawn_actor_from_class(unreal.WaterZone, unreal.Vector(0.0, 0.0, 0.0), unreal.Rotator(0.0, 0.0, 0.0))
    zone.set_actor_label("WaterZone")
    zone.set_folder_path("Roam/Water")
    zone.set_editor_property("zone_extent", unreal.Vector2D(600000.0, 600000.0))
    zone.set_editor_property("render_target_resolution", unreal.IntPoint(2048, 2048))
    ocean = W.actors.spawn_actor_from_class(unreal.WaterBodyOcean, unreal.Vector(0.0, 0.0, 0.0), unreal.Rotator(0.0, 0.0, 0.0))
    ocean.set_actor_label("Ocean")
    ocean.set_folder_path("Roam/Water")
    comp = ocean.get_component_by_class(unreal.WaterBodyOceanComponent)
    comp.set_editor_property("affects_landscape", False)
    comp.set_editor_property("ocean_extents", unreal.Vector2D(600000.0, 600000.0))
    W.log("OCEAN_PLUGIN spawned zone + ocean (experimental)")


def build():
    if W.option("OCEAN", "plane") == "plugin":
        try:
            _plugin_ocean()
            return
        except Exception as exc:  # noqa: BLE001
            W.warn("Water plugin ocean failed (%r) - falling back to the water plane" % (exc,))
    # the materials agent owns the real sea master (Tools/ue/materials_m_fx.py -> M_Roam_Water_Simple); our own M_Roam_Sea is only the fallback
    shared = "/Game/Forza/Materials/M_Roam_Water_Simple"
    if W.ea.does_asset_exist(shared):
        W.log("SEA_MATERIAL using shared %s" % shared)
        _plane(W.load(shared))
    else:
        W.warn("%s missing (run the materials job server 'fx' step) - building the fallback %s" % (shared, SEA_MAT))
        _plane(_build_material())
