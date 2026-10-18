"""Builds /Game/Forza/Maps/L_Test - the flat test map of the C++ skeleton - and the project physical materials.

Run (headless, re-runnable, overwrites the map):
    powershell -File Tools/ue_cmd.ps1 -PythonScript Tools/ue/make_test_map.py -LogName make_test_map

Creates
  * /Game/Forza/Materials/Physical/PM_Roam_<Surface>   one physical material per ERoamSurface (SurfaceType1..8); Friction = base grip
  * /Game/Forza/Maps/L_Test                           4 km x 4 km flat ground (engine cube scaled, "RoamWorldStatic" collision profile,
                                                      asphalt physical material), a gentle ramp, PlayerStart, DirectionalLight + SkyAtmosphere +
                                                      SkyLight, GameMode override = RoamGameMode
Log markers: ROAM_MAP_*  (grep them).
"""
import math

import unreal

MAP_PATH = "/Game/Forza/Maps/L_Test"
PM_DIR = "/Game/Forza/Materials/Physical"

# (name, ERoamSurface index, Friction (= dry base grip multiplier), StaticFriction, Density)
SURFACES = [
    ("Asphalt", 0, 1.00, 1.00, 2.4),
    ("Concrete", 1, 0.97, 0.97, 2.4),
    ("Dirt", 2, 0.78, 0.80, 1.6),
    ("Gravel", 3, 0.70, 0.72, 1.8),
    ("Grass", 4, 0.60, 0.62, 1.2),
    ("Sand", 5, 0.55, 0.58, 1.6),
    ("Snow", 6, 0.35, 0.40, 0.5),
    ("Mud", 7, 0.45, 0.50, 1.4),
]

assets = unreal.EditorAssetLibrary
tools = unreal.AssetToolsHelpers.get_asset_tools()
actors = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)


def make_physical_materials():
    created = {}
    for name, index, friction, static_friction, density in SURFACES:
        path = "%s/PM_Roam_%s" % (PM_DIR, name)
        if assets.does_asset_exist(path):
            pm = assets.load_asset(path)
        else:
            pm = tools.create_asset("PM_Roam_" + name, PM_DIR, unreal.PhysicalMaterial, unreal.PhysicalMaterialFactoryNew())
        unreal.RoamEditorLibrary.configure_roam_physical_material(pm, index, friction, static_friction, density)
        assets.save_loaded_asset(pm)
        created[name] = pm
        unreal.log("ROAM_MAP_PM %s surface_index=%d friction=%.2f" % (path, index, friction))
    return created


def spawn_static_mesh(label, mesh_path, location, rotation, scale, phys_material):
    actor = actors.spawn_actor_from_class(unreal.StaticMeshActor, location, rotation)
    actor.set_actor_label(label)
    actor.set_folder_path("Roam/Test")
    actor.set_actor_scale3d(scale)
    component = actor.static_mesh_component
    component.set_static_mesh(assets.load_asset(mesh_path))
    # World-aligned grid: gives a sense of speed on the empty plane (the default cube material tiles per object UV and smears at 4 km scale).
    component.set_material(0, assets.load_asset("/Engine/EngineMaterials/WorldGridMaterial"))
    component.set_mobility(unreal.ComponentMobility.STATIC)
    # Roam collision profile (ObjectType WorldStatic, blocks Roam_Wheel / Roam_Camera / Roam_Vehicle / Roam_Traffic).
    component.set_collision_profile_name("RoamWorldStatic")
    unreal.RoamEditorLibrary.set_component_physical_material(component, phys_material)
    return actor


def main():
    pms = make_physical_materials()

    world = unreal.EditorLoadingAndSavingUtils.new_blank_map(False)
    unreal.log("ROAM_MAP_NEW world=%s" % world.get_name())

    # ---- ground: 4 km x 4 km, top surface at z = 0 -----------------------------------------------------------------
    ground = spawn_static_mesh(
        "TestGround", "/Engine/BasicShapes/Cube.Cube",
        unreal.Vector(0.0, 0.0, -100.0), unreal.Rotator(0.0, 0.0, 0.0), unreal.Vector(4000.0, 4000.0, 2.0), pms["Asphalt"])

    # ---- gentle ramp: 40 m long, 8 m wide, 5 degrees, low end flush with the ground, starts 60 m ahead of the spawn ---
    length_cm, width_cm, thickness_cm, pitch = 4000.0, 800.0, 50.0, 5.0
    half = 0.5 * length_cm
    centre_z = half * math.sin(math.radians(pitch)) - 0.5 * thickness_cm * math.cos(math.radians(pitch))
    centre_x = 6000.0 + half * math.cos(math.radians(pitch))
    spawn_static_mesh(
        "TestRamp", "/Engine/BasicShapes/Cube.Cube",
        unreal.Vector(centre_x, 0.0, centre_z), unreal.Rotator(0.0, pitch, 0.0),
        unreal.Vector(length_cm / 100.0, width_cm / 100.0, thickness_cm / 100.0), pms["Asphalt"])

    # ---- player start ---------------------------------------------------------------------------------------------
    start = actors.spawn_actor_from_class(unreal.PlayerStart, unreal.Vector(0.0, 0.0, 120.0), unreal.Rotator(0.0, 0.0, 0.0))
    start.set_actor_label("PlayerStart")
    start.set_folder_path("Roam/Test")

    # ---- lighting: sun + atmosphere + real-time sky light (all movable: r.AllowStaticLighting=False) -------------------
    sun = actors.spawn_actor_from_class(unreal.DirectionalLight, unreal.Vector(0.0, 0.0, 500.0), unreal.Rotator(0.0, -45.0, 35.0))  # NOTE: unreal.Rotator(roll, pitch, yaw)
    sun.set_actor_label("Sun")
    sun.set_folder_path("Roam/Test")
    sun_component = sun.get_component_by_class(unreal.DirectionalLightComponent)
    sun_component.set_mobility(unreal.ComponentMobility.MOVABLE)
    sun_component.set_editor_property("atmosphere_sun_light", True)
    sun_component.set_editor_property("atmosphere_sun_light_index", 0)
    # Physical sun (lux). The project uses the EXTENDED default luminance range (r.DefaultFeature.AutoExposure.ExtendDefaultLuminanceRange),
    # i.e. exposure is calibrated for physically based values; 10 lux (the old template value) renders black. See Docs/Tech/FH5_weather_time.md 8.3.
    sun_component.set_editor_property("intensity", 110000.0)

    atmosphere = actors.spawn_actor_from_class(unreal.SkyAtmosphere, unreal.Vector(0.0, 0.0, 0.0), unreal.Rotator(0.0, 0.0, 0.0))
    atmosphere.set_actor_label("SkyAtmosphere")
    atmosphere.set_folder_path("Roam/Test")

    sky_light = actors.spawn_actor_from_class(unreal.SkyLight, unreal.Vector(0.0, 0.0, 300.0), unreal.Rotator(0.0, 0.0, 0.0))
    sky_light.set_actor_label("SkyLight")
    sky_light.set_folder_path("Roam/Test")
    sky_component = sky_light.get_component_by_class(unreal.SkyLightComponent)
    sky_component.set_mobility(unreal.ComponentMobility.MOVABLE)
    sky_component.set_editor_property("real_time_capture", True)

    fog = actors.spawn_actor_from_class(unreal.ExponentialHeightFog, unreal.Vector(0.0, 0.0, 0.0), unreal.Rotator(0.0, 0.0, 0.0))
    fog.set_actor_label("HeightFog")
    fog.set_folder_path("Roam/Test")

    # ---- game mode override -----------------------------------------------------------------------------------------
    ok = unreal.RoamEditorLibrary.set_world_game_mode_override(world, unreal.RoamGameMode.static_class())
    unreal.log("ROAM_MAP_GAMEMODE_OVERRIDE ok=%s" % ok)

    # ---- save -------------------------------------------------------------------------------------------------------
    saved = unreal.EditorLoadingAndSavingUtils.save_map(world, MAP_PATH)
    unreal.log("ROAM_MAP_SAVED path=%s ok=%s exists=%s" % (MAP_PATH, saved, assets.does_asset_exist(MAP_PATH)))


try:
    main()
except Exception as exc:  # noqa: BLE001 - always report, always quit
    unreal.log_error("ROAM_MAP_EXCEPTION %r" % (exc,))

unreal.SystemLibrary.execute_console_command(None, "QUIT_EDITOR")
