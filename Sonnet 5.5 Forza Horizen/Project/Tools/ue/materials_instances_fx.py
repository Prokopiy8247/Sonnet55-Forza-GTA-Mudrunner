"""Instances of the water / glass / particle / decal masters (materials_m_fx.py, materials_m_surface.py glass); registered by materials_instances.build_all.
Parameter names follow the masters: water (FlowSpeed, TileMetresA/B, NormalStrength, WaveWeightA/B/C, ShallowColor, DeepColor, FoamColor, ScatteringColor,
AbsorptionColor, DensityScale, DepthScaleCm, WhiteCapAmount ...), particles (SpriteTex, Tint, OpacityScale, SoftDepthCm, NearFadeCm, SelfGlow / Brightness),
skid (MarkBaseColorTex / MarkNormalTex / MarkORMTex, TilesAlong, Opacity, OpacityScale)."""


def register(I):
    srgb, T = I.srgb, I.T
    # ---- water (Single Layer Water when it compiles, else translucent depth-fade: both read the colour params below)
    I.add("MI_Water_Sea", "M_Roam_Water_Simple", None, note="open sea / default fallback")
    I.add("MI_Water_Lake", "M_Roam_Water_Simple", None,
          {"NormalStrength": 0.5, "WaveWeightB": 0.45, "WaveWeightC": 0.2, "FlowSpeed": 0.2, "WhiteCapAmount": 0.0},
          {"ShallowColor": (0.05, 0.20, 0.19, 1), "DeepColor": (0.01, 0.07, 0.09, 1), "ScatteringColor": (0.006, 0.014, 0.012, 1)}, note="calm lake")
    I.add("MI_Water_Pond", "M_Roam_Water_Simple", None,
          {"NormalStrength": 0.25, "WaveWeightB": 0.25, "FlowSpeed": 0.08, "WhiteCapAmount": 0.0, "DensityScale": 3.0, "DepthScaleCm": 250.0},
          {"ShallowColor": (0.06, 0.15, 0.07, 1), "DeepColor": (0.02, 0.06, 0.035, 1), "ScatteringColor": (0.012, 0.02, 0.006, 1)}, note="small green pond")
    I.add("MI_Water_River", "M_Roam_Water_River", None, note="river / stream; flows along MPC WindDirection (or mesh UV v with UseMeshUV = 1)")
    I.add("MI_Water_River_Muddy", "M_Roam_Water_River", None, {"DensityScale": 3.0, "DepthScaleCm": 220.0, "WhiteCapAmount": 0.05},
          {"ShallowColor": (0.17, 0.13, 0.07, 1), "DeepColor": (0.08, 0.06, 0.035, 1), "ScatteringColor": (0.03, 0.024, 0.012, 1),
           "AbsorptionColor": (0.35, 0.40, 0.55, 1)}, note="brown muddy river")
    # ---- glass (translucent building glass master without the window grid)
    glass_common = {"WindowGridEnabled": 0.0, "DirtAmount": 0.2}
    I.add("MI_RS_Glass", "M_Roam_Glass_Building", "M_RS_Glass", dict(glass_common, OpacityFacing=0.22, OpacityGrazing=0.7, GlassRoughness=0.05),
          {"GlassColor": tuple(c * 0.55 for c in srgb("#a9c8d0")[:3]) + (1,)}, note="bus-stop shelter glass")
    I.add("MI_Glass_Tinted", "M_Roam_Glass_Building", None, dict(glass_common, OpacityFacing=0.4, OpacityGrazing=0.9), {"GlassColor": (0.015, 0.03, 0.035, 1)},
          note="dark tinted glass")
    # ---- particles (SpriteTex alpha = coverage; Niagara particle colour multiplies Tint while UseParticleColor = 1)
    dust = {"SpriteTex": T.tex_path("dust_puff_sprite", "BC")}
    smoke = {"SpriteTex": T.tex_path("smoke_puff_sprite", "BC")}
    I.add("MI_Particle_Dust", "M_Roam_Particle_Soft", None, {"OpacityScale": 0.7, "SoftDepthCm": 150.0}, {"Tint": (1.0, 0.92, 0.80, 1)}, textures=dust,
          note="tyre dust on dirt / sand")
    I.add("MI_Particle_Dust_Light", "M_Roam_Particle_Soft", None, {"OpacityScale": 0.5, "SoftDepthCm": 150.0}, {"Tint": (1.1, 1.05, 0.95, 1)}, textures=dust)
    I.add("MI_Particle_Smoke", "M_Roam_Particle_Soft", None, {"OpacityScale": 0.8, "SoftDepthCm": 120.0}, {"Tint": (0.45, 0.45, 0.47, 1)}, textures=smoke,
          note="exhaust / engine smoke")
    I.add("MI_Particle_Smoke_Tyre", "M_Roam_Particle_Soft", None, {"OpacityScale": 0.75, "SoftDepthCm": 120.0}, {"Tint": (0.85, 0.85, 0.87, 1)}, textures=smoke,
          note="burnout / drift tyre smoke (white-grey)")
    I.add("MI_Particle_Spray", "M_Roam_Particle_Soft", None, {"OpacityScale": 0.45, "SoftDepthCm": 100.0}, {"Tint": (0.85, 0.9, 0.95, 1)}, textures=smoke,
          note="wet-road spray")
    I.add("MI_Particle_Snow", "M_Roam_Particle_Soft", None, {"OpacityScale": 0.8, "SoftDepthCm": 100.0, "SelfGlow": 0.25}, {"Tint": (0.95, 0.97, 1.0, 1)},
          textures=dust, note="snow powder")
    I.add("MI_Particle_Smoke_Unlit", "M_Roam_Particle_Unlit", None, {"OpacityScale": 0.6, "Brightness": 0.35}, {"Tint": (0.6, 0.6, 0.62, 1)}, textures=smoke,
          note="cheap unlit smoke")
    I.add("MI_Particle_Spark", "M_Roam_Particle_Unlit", None, {"OpacityScale": 1.0, "Brightness": 12.0, "SoftDepthCm": 5.0}, {"Tint": (1.0, 0.55, 0.15, 1)},
          textures=dust, base_overrides={"override_blend_mode": True, "blend_mode": I.unreal.BlendMode.BLEND_ADDITIVE}, note="additive sparks / glow")
    # ---- tyre-mark decals (box 0.4 m wide, long axis = decal local Y: TilesAlong = length / 3 m)
    tm = {"MarkBaseColorTex": T.tex_path("tire_mark", "BC"), "MarkNormalTex": T.tex_path("tire_mark", "N"), "MarkORMTex": T.tex_path("tire_mark", "ORM")}
    sk = {"MarkBaseColorTex": T.tex_path("skid_dirt", "BC"), "MarkNormalTex": T.tex_path("skid_dirt", "N"), "MarkORMTex": T.tex_path("skid_dirt", "ORM")}
    I.add("MI_Skid_Tire", "M_Roam_Skid", None, {"OpacityScale": 0.85, "TilesAlong": 4.0}, textures=tm, note="rubber skid on asphalt")
    I.add("MI_Skid_Dirt", "M_Roam_Skid", None, {"OpacityScale": 0.9, "TilesAlong": 3.0, "NormalStrength": 0.9}, textures=sk, note="drift groove on dirt / gravel (0.8 m wide)")
