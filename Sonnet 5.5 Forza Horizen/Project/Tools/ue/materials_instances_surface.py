"""Instances of the road / structure / roadside / building masters (registered by materials_instances.build_all via register(I)).  Owner: agent M-B.

  roads + structures   /Game/Forza/Materials/Roads/MI_<slot without 'M_'>          (R's Tools/ue/import_roads.py loads exactly these)
                       M_Road_Asphalt/Concrete/Dirt/Gravel/Marking, M_Curb, M_Bridge_Concrete/Steel, M_Tunnel_Wall/Light  (+ extras MI_Road_AsphaltWorn ...)
  roadside kit         /Game/Forza/Materials/Instances/MI_RS_*   one per M_RS_* slot of Exports/Roadside (base colours / metallic / roughness / emission
                       are the Blender kit values of Tools/blender/roadside/rs_lib.py); tinted slots (concrete, wood, stone, hay, soil, rust ...) use the
                       textured M_Roam_Building with a tint computed from the texture albedo so the mean colour matches the kit colour.
  generic buildings    MI_Bld_* (M_Bld_* slots of Docs/BLENDER_CONTRACT.md section 4), MI_Metal_Galv, MI_Sign_*
"""
import json

ROADS_DIR = "/Game/Forza/Materials/Roads"
_MAN = {}


def _manifest(I):
    if not _MAN:
        with open(I.T.SRC + "/manifest.json", "r", encoding="utf-8") as fh:
            for s in json.load(fh)["sets"]:
                _MAN[s["name"]] = s
    return _MAN


def _lin(c8):
    c = c8 / 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def tint_for(I, setname, hexcol, gain=1.0):
    """BaseTint (linear rgba) that moves the mean colour of texture set `setname` to the sRGB colour `hexcol`."""
    mean = _manifest(I)[setname]["albedo_mean_srgb_rgb"]
    h = hexcol.lstrip("#")
    tgt = [int(h[i:i + 2], 16) for i in (0, 2, 4)]
    out = []
    for m, t in zip(mean, tgt):
        out.append(min(4.0, max(0.15, gain * _lin(t) / max(_lin(m), 1e-3))))
    return tuple(out) + (1.0,)


def register(I):
    srgb, pbr, add = I.srgb, I.pbr, I.add
    R = ROADS_DIR

    # ============================================================================== roads (folder Roads)
    asph = pbr("asphalt_new")
    add("MI_Road_Asphalt", "M_Roam_Road", "M_Road_Asphalt", {"TileMetres": 3.0, "ShoulderTintAmount": 0.45, "MarkingWear": 0.3, "CentreStyle": 0, "SpecularBase": 0.5},
        {"ShoulderTint": (0.85, 0.82, 0.76, 1)}, textures=asph, folder=R, note="default asphalt carriageway + shoulders, lane paint from UV1..UV3")
    add("MI_Road_AsphaltNew", "M_Roam_Road", None, {"TileMetres": 3.0, "ShoulderTintAmount": 0.35, "MarkingWear": 0.12, "WheelTrackDarkening": 0.2},
        {"ShoulderTint": (0.9, 0.88, 0.84, 1)}, textures=asph, folder=R, note="fresh asphalt (highways)")
    add("MI_Road_AsphaltWorn", "M_Roam_Road", None, {"TileMetres": 4.0, "ShoulderTintAmount": 0.55, "MarkingWear": 0.75, "WheelTrackDarkening": 0.5, "MacroVariation": 1.4,
                                                    "DustResponse": 1.2}, {"ShoulderTint": (0.8, 0.76, 0.7, 1)}, textures=pbr("asphalt_worn"), folder=R,
        note="cracked / patched asphalt (mountain + village roads)")
    add("MI_Road_AsphaltMountain", "M_Roam_Road", None, {"TileMetres": 4.0, "ShoulderTintAmount": 0.5, "MarkingWear": 0.6, "CentreStyle": 1, "WheelTrackDarkening": 0.4,
                                                        "MacroVariation": 1.2}, {"ShoulderTint": (0.8, 0.76, 0.7, 1)}, textures=pbr("asphalt_worn"), folder=R,
        note="mountain road: worn asphalt with a SOLID centre line")
    add("MI_Road_Concrete", "M_Roam_Road", "M_Road_Concrete", {"TileMetres": 6.0, "MarkingsEnabled": 0.0, "WheelTrackDarkening": 0.12, "SpecularBase": 0.45,
                                                              "MacroVariation": 1.2}, textures=pbr("concrete_road"), folder=R,
        note="concrete road slabs / median barrier (no paint)")
    add("MI_Road_Dirt", "M_Roam_Road", "M_Road_Dirt", {"AcrossMode": 1.0, "AntiTileAmount": 0.0, "MarkingsEnabled": 0.0, "WheelTrackDarkening": 0.0, "SpecularBase": 0.3,
                                                      "ShoulderSetMix": 1.0, "DustResponse": 1.3, "WetnessResponse": 1.0, "MacroVariation": 0.8},
        textures=dict(pbr("dirt_road_rut"), **pbr("dirt_road", ("ShoulderBaseColorTex", "ShoulderNormalTex", "ShoulderORMTex"))),
        switches={"UseShoulderSet": True}, folder=R,
        note="dirt road: rut texture spans the paved width (UV2.x), the plain dirt texture on shoulders (zone < 1)")
    add("MI_Road_Gravel", "M_Roam_Road", "M_Road_Gravel", {"TileMetres": 2.0, "MarkingsEnabled": 0.0, "WheelTrackDarkening": 0.0, "SpecularBase": 0.3,
                                                          "DustResponse": 1.2, "MacroVariation": 0.9}, textures=pbr("gravel"), folder=R,
        note="gravel shoulder strip / gravel road")
    add("MI_Road_Cobble", "M_Roam_Road", None, {"TileMetres": 2.0, "MarkingsEnabled": 0.0, "WheelTrackDarkening": 0.1}, textures=pbr("cobblestone"), folder=R,
        note="cobblestone paving (village squares, optional)")
    add("MI_Road_Marking", "M_Roam_Roadside", "M_Road_Marking", {"Metallic": 0.0, "Roughness": 0.6, "ColorBreakup": 0.15, "RoughnessBreakup": 0.2, "VertexColorTint": 0.0,
                                                                 "RetroReflective": 0.8, "SpecularBase": 0.5},
        {"BaseColor": (0.60, 0.60, 0.56, 1)}, folder=R, note="solid paint strip geometry (stop lines, hatching): same white as the procedural lane paint")

    # ---- structures (road chunk UV1 is metric on every chunk surface/structure => UseUV1)
    uv1 = {"UseUV1": True}
    add("MI_Curb", "M_Roam_Building", "M_Curb", {"TileMetres": 2.0, "VertexColorTint": 0.0, "MacroVariation": 0.5, "SnowResponse": 0.3},
        {"BaseTint": (0.95, 0.93, 0.88, 1)}, textures=pbr("curb_concrete"), switches=uv1, folder=R, note="concrete kerb (kerb runs along V = arc length)")
    add("MI_Bridge_Concrete", "M_Roam_Building", "M_Bridge_Concrete", {"TileMetres": 2.0, "VertexColorTint": 0.0, "MacroVariation": 0.7},
        {"BaseTint": tint_for(I, "concrete_rough", "#9b9b97")}, textures=pbr("concrete_rough"), switches=uv1, folder=R,
        note="bridge deck underside, piers, abutments, parapets")
    add("MI_Bridge_Steel", "M_Roam_Building", "M_Bridge_Steel", {"TileMetres": 1.0, "VertexColorTint": 0.0, "MacroVariation": 0.5, "SpecularBase": 0.5},
        {"BaseTint": tint_for(I, "metal_painted_galvanized", "#767c82")}, textures=pbr("metal_painted_galvanized"), switches=uv1, folder=R,
        note="bridge girders / cables / railings: painted galvanised steel (grey-blue steel; tint pulls the teal texture to #767c82)")
    add("MI_Tunnel_Wall", "M_Roam_Building", "M_Tunnel_Wall", {"TileMetres": 2.0, "VertexColorTint": 0.0, "MacroVariation": 0.8, "RoughnessScale": 1.05},
        {"BaseTint": tint_for(I, "concrete_rough", "#8a8272")}, textures=pbr("concrete_rough"), switches=uv1, folder=R,
        note="tunnel liner and portal head walls")
    add("MI_Tunnel_Light", "M_Roam_Roadside", "M_Tunnel_Light",
        {"Metallic": 0.0, "Roughness": 0.5, "EmissionMode": 1.0, "EmissiveIntensity": 1200.0, "ColorBreakup": 0.0, "RoughnessBreakup": 0.0, "VertexColorTint": 0.0},
        {"BaseColor": srgb("#fff1d0"), "EmissiveColor": srgb("#ffe0a0")}, folder=R, note="tunnel ceiling lamp strip (always on)")

    # ============================================================================== roadside kit (folder Instances)
    def rs(name, hexcol, metal, rough, emission=None, retro=0.0, breakup=0.12, note="", rough_breakup=0.2, sc=None, vc=1.0, spec=0.5):
        scal = {"Metallic": metal, "Roughness": rough, "RetroReflective": retro, "ColorBreakup": breakup, "RoughnessBreakup": rough_breakup, "VertexColorTint": vc,
                "SpecularBase": spec}
        vec = {"BaseColor": srgb(hexcol)}
        if emission:
            scal.update(EmissionMode=emission[2], EmissiveIntensity=emission[1])
            vec["EmissiveColor"] = srgb(emission[0])
        if sc:
            scal.update(sc)
        add("MI_" + name[2:], "M_Roam_Roadside", name, scal, vec, note=note)

    # colours / metallic / roughness from Tools/blender/roadside/rs_lib.py (the Blender previews)
    rs("M_RS_GalvSteel", "#a4a9ae", 0.9, 0.40, breakup=0.10, note="zinc-coated steel rails, posts, tubes")
    rs("M_RS_GalvDark", "#5d6268", 0.85, 0.50, note="dark galvanised hardware")
    rs("M_RS_PaintWhite", "#ecece8", 0.0, 0.50)
    rs("M_RS_PaintRed", "#c3231c", 0.0, 0.45)
    rs("M_RS_PaintBlack", "#1d1e20", 0.0, 0.55)
    rs("M_RS_PaintYellow", "#f0bf00", 0.0, 0.50)
    rs("M_RS_PaintGrey", "#6c7075", 0.1, 0.55, note="powder-coated steel")
    rs("M_RS_PlasticOrange", "#f0580c", 0.0, 0.42, spec=0.55, note="cones, drums, bollards")
    rs("M_RS_PlasticWhite", "#efeeea", 0.0, 0.40, spec=0.55, note="delineator posts")
    rs("M_RS_PlasticGrey", "#55595e", 0.0, 0.50)
    rs("M_RS_Rubber", "#171717", 0.0, 0.88, spec=0.3)
    rs("M_RS_ReflectorRed", "#d4161b", 0.0, 0.15, emission=("#ff2020", 0.6, 2.0), retro=2.2, breakup=0.0, rough_breakup=0.0, note="retro-reflective red")
    rs("M_RS_ReflectorWhite", "#f2f2f2", 0.0, 0.15, emission=("#ffffff", 0.5, 2.0), retro=2.2, breakup=0.0, rough_breakup=0.0, note="retro-reflective white")
    rs("M_RS_ReflectorAmber", "#ffa400", 0.0, 0.15, emission=("#ffa000", 0.6, 2.0), retro=2.2, breakup=0.0, rough_breakup=0.0, note="retro-reflective amber")
    sign = dict(retro=1.6, breakup=0.04, rough_breakup=0.05)
    rs("M_RS_SignWhite", "#f2f2ef", 0.0, 0.33, retro=2.0, breakup=0.04, rough_breakup=0.05, note="sign faces / lettering (retro-reflective)")
    rs("M_RS_SignRed", "#c9191d", 0.0, 0.33, **sign)
    rs("M_RS_SignBlack", "#111214", 0.0, 0.40, retro=0.3, breakup=0.03, rough_breakup=0.05)
    rs("M_RS_SignBlue", "#0a4aa0", 0.0, 0.33, **sign)
    rs("M_RS_SignYellow", "#f6c500", 0.0, 0.33, retro=2.0, breakup=0.04, rough_breakup=0.05)
    rs("M_RS_SignGreen", "#0a6b3b", 0.0, 0.33, **sign)
    rs("M_RS_SignBack", "#8b9096", 0.75, 0.48, note="folded sign rim and back")
    rs("M_RS_LampLens", "#fff4d8", 0.0, 0.15, emission=("#fff1cf", 25.0, 2.0), breakup=0.0, rough_breakup=0.0,
       note="street lamp / gantry lens: emissive at night (MPC TimeOfDay / NightFactor)")
    rs("M_RS_Insulator", "#5b6b5a", 0.0, 0.18, breakup=0.05, spec=0.6)
    rs("M_RS_Wire", "#2b2c2e", 0.6, 0.40, breakup=0.05)
    rs("M_RS_Rope", "#8d6e3c", 0.0, 0.90, breakup=0.2)
    rs("M_RS_Grating", "#4a4e53", 0.8, 0.55)
    rs("M_RS_TyreRubber", "#1c1c1d", 0.0, 0.86, spec=0.3, note="tyre stack rubber")
    rs("M_RS_TyrePaint", "#e7e5dd", 0.0, 0.72, breakup=0.3, note="white tyre paint")

    # ---- tinted + textured slots (M_Roam_Building)
    def bld(name, setname, hexcol, tile, rough_scale=1.0, note="", scal=None, gain=1.0, extra_vec=None):
        sc = {"TileMetres": tile, "VertexColorTint": 1.0, "RoughnessScale": rough_scale, "MacroVariation": 0.6}
        if scal:
            sc.update(scal)
        vec = {"BaseTint": tint_for(I, setname, hexcol, gain)}
        if extra_vec:
            vec.update(extra_vec)
        add("MI_" + name[2:], "M_Roam_Building", name, sc, vec, textures=pbr(setname), note=note)

    bld("M_RS_Concrete", "concrete_rough", "#a29f98", 2.0, note="cast concrete (vertex colour = dirt gradient)")
    bld("M_RS_ConcreteDark", "concrete_rough", "#6f6d68", 2.0, note="stained / wet concrete, kerbs")
    bld("M_RS_Wood", "wood_planks_weathered", "#7c5532", 2.0, note="timber")
    bld("M_RS_WoodPale", "wood_planks_weathered", "#b8935f", 2.0, note="bench slats")
    bld("M_RS_Stone", "stone_wall", "#8d867b", 2.0, note="granite / dry stone (vertex colour tint)")
    bld("M_RS_Mortar", "concrete_rough", "#6e6a63", 2.0, note="core between stones")
    bld("M_RS_Hay", "field_wheat", "#cfae52", 1.5, note="straw (field_wheat texture)", scal={"MacroVariation": 1.0})
    bld("M_RS_Soil", "dirt_road", "#5a4631", 4.0, note="soil mound at post feet")
    bld("M_RS_Rust", "rust_overlay", "#6b3f26", 1.0, note="rusted steel (rust_overlay texture as albedo)", scal={"MetallicScale": 0.5})

    # ---- billboards (ad A/B/C swap)
    for suffix, ad in (("", "A"), ("_B", "B"), ("_C", "C")):
        add("MI_RS_BillboardFace" + suffix, "M_Roam_Billboard", "M_RS_BillboardFace" + suffix, {"NightGlow": 0.35},
            textures={"AdTex": I.T.TEX_ROOT + "/Roadside/T_RS_BillboardAd_" + ad}, note="billboard face, ad " + ad)

    # ============================================================================== generic building kit names (BLENDER_CONTRACT section 4)
    bs = {"VertexColorTint": 1.0, "MacroVariation": 0.6}
    add("MI_Bld_Plaster", "M_Roam_Building", "M_Bld_Plaster", dict(bs, TileMetres=2.0), textures=pbr("plaster_white"), note="whitewashed plaster")
    add("MI_Bld_PlasterOchre", "M_Roam_Building", "M_Bld_PlasterOchre", dict(bs, TileMetres=2.0), textures=pbr("plaster_ochre"), note="ochre plaster")
    add("MI_Bld_Brick", "M_Roam_Building", "M_Bld_Brick", dict(bs, TileMetres=1.35), textures=pbr("brick_red"), note="red brick, running bond")
    add("MI_Bld_Stone", "M_Roam_Building", "M_Bld_Stone", dict(bs, TileMetres=2.0), textures=pbr("stone_wall"), note="rubble stone masonry")
    add("MI_Bld_Concrete", "M_Roam_Building", "M_Bld_Concrete", dict(bs, TileMetres=2.0), textures=pbr("concrete_rough"), note="board-formed concrete")
    add("MI_Bld_Wood", "M_Roam_Building", "M_Bld_Wood", dict(bs, TileMetres=2.0), textures=pbr("wood_planks_weathered"), note="weathered timber planks")
    add("MI_Bld_WoodDark", "M_Roam_Building", "M_Bld_WoodDark", dict(bs, TileMetres=2.0), textures=pbr("wood_dark"), note="dark stained hardwood")
    add("MI_Bld_RoofTile", "M_Roam_Building", "M_Bld_RoofTile", dict(bs, TileMetres=2.0, SnowResponse=1.0), textures=pbr("roof_tile_terracotta"),
        note="terracotta barrel tiles (courses along U)")
    add("MI_Bld_RoofSlate", "M_Roam_Building", "M_Bld_RoofSlate", dict(bs, TileMetres=1.8, SnowResponse=1.0), textures=pbr("roof_slate"), note="slate roof")
    add("MI_Bld_Corrugated", "M_Roam_Building", "M_Bld_Corrugated", dict(bs, TileMetres=1.0, SnowResponse=0.8), textures=pbr("metal_corrugated"),
        note="corrugated sheet (barns, sheds)")
    add("MI_Bld_MetalPainted", "M_Roam_Building", "M_Bld_MetalPainted", dict(bs, TileMetres=1.0), textures=pbr("metal_painted_galvanized"), note="painted galvanised panels")
    add("MI_Metal_Galv", "M_Roam_Roadside", "M_Metal_Galv", {"Metallic": 0.9, "Roughness": 0.4, "ColorBreakup": 0.1}, {"BaseColor": srgb("#a4a9ae")},
        note="generic galvanised steel")
    for nm, hexcol, retro in (("Blue", "#0a4aa0", 1.6), ("Red", "#c9191d", 1.6), ("White", "#f2f2ef", 2.0), ("Yellow", "#f6c500", 2.0), ("Green", "#0a6b3b", 1.6)):
        add("MI_Sign_" + nm, "M_Roam_Roadside", "M_Sign_" + nm, {"Metallic": 0.0, "Roughness": 0.33, "RetroReflective": retro, "ColorBreakup": 0.04, "RoughnessBreakup": 0.05},
            {"BaseColor": srgb(hexcol)}, note="generic sign face (" + nm + ")")
    # window glass of buildings (own windows grid, lit at night)
    add("MI_Bld_Glass", "M_Roam_Glass_Building", "M_Bld_Glass", {"LitFraction": 0.35}, {"GlassColor": (0.10, 0.17, 0.2, 1)}, note="building windows (grid from UV0 metres)")
    add("MI_Bld_Glass_Shop", "M_Roam_Glass_Building", "M_Bld_Glass_Shop", {"WindowWidth": 3.0, "WindowHeight": 2.2, "LitFraction": 0.6, "LitIntensity": 8.0},
        {"GlassColor": (0.12, 0.2, 0.22, 1)}, note="shop windows (large, mostly lit at night)")
