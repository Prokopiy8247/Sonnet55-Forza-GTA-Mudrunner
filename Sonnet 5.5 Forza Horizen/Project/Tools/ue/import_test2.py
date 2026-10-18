import unreal

FBX = unreal.Paths.project_dir() + "Exports/Test/PipelineTest.fbx"
DEST = "/Game/Forza/Test2"

pipeline = unreal.InterchangeGenericAssetsPipeline()
cm = pipeline.common_meshes_properties
cm.set_editor_property("bake_meshes", False)
cm.set_editor_property("bake_pivot_meshes", False)
cm.set_editor_property("import_sockets", True)
pipeline.set_editor_property("import_offset_translation", unreal.Vector(0, 0, 0))
mp = pipeline.mesh_pipeline
mp.set_editor_property("combine_static_meshes_behavior", unreal.InterchangeCombineStaticMeshesBehavior.DO_NOT_COMBINE)
mp.set_editor_property("build_nanite", False)
mp.set_editor_property("generate_lightmap_u_vs", False)
mp.set_editor_property("collision", True)
mp.set_editor_property("fallback_collision_type", unreal.InterchangeMeshCollision.NONE)
mp.set_editor_property("import_collision_according_to_mesh_name", True)

task = unreal.AssetImportTask()
task.set_editor_property("filename", FBX)
task.set_editor_property("destination_path", DEST)
task.set_editor_property("automated", True)
task.set_editor_property("replace_existing", True)
task.set_editor_property("save", True)
task.set_editor_property("options", pipeline)
unreal.AssetToolsHelpers.get_asset_tools().import_asset_tasks([task])
paths = list(task.get_editor_property("imported_object_paths"))
unreal.log("IMPORTED2: " + str(paths))
for p in paths:
    a = unreal.EditorAssetLibrary.load_asset(p)
    if isinstance(a, unreal.StaticMesh):
        b = a.get_bounds()
        unreal.log("BOUNDS2 %s origin=(%.1f,%.1f,%.1f) extent=(%.1f,%.1f,%.1f)" % (p, b.origin.x, b.origin.y, b.origin.z, b.box_extent.x, b.box_extent.y, b.box_extent.z))
unreal.SystemLibrary.execute_console_command(None, "QUIT_EDITOR")
