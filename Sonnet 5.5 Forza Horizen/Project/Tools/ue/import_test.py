import unreal

FBX = unreal.Paths.project_dir() + "Exports/Test/PipelineTest.fbx"
DEST = "/Game/Forza/Test"

def make_task(fbx, dest, combine=False):
    task = unreal.AssetImportTask()
    task.set_editor_property("filename", fbx)
    task.set_editor_property("destination_path", dest)
    task.set_editor_property("automated", True)
    task.set_editor_property("replace_existing", True)
    task.set_editor_property("save", True)
    ui = unreal.FbxImportUI()
    ui.set_editor_property("import_mesh", True)
    ui.set_editor_property("import_as_skeletal", False)
    ui.set_editor_property("import_materials", True)
    ui.set_editor_property("import_textures", False)
    ui.set_editor_property("import_animations", False)
    sm = ui.static_mesh_import_data
    sm.set_editor_property("combine_meshes", combine)
    sm.set_editor_property("auto_generate_collision", False)
    sm.set_editor_property("generate_lightmap_u_vs", False)
    sm.set_editor_property("build_nanite", False)
    task.set_editor_property("options", ui)
    return task

task = make_task(FBX, DEST)
unreal.AssetToolsHelpers.get_asset_tools().import_asset_tasks([task])
paths = list(task.get_editor_property("imported_object_paths"))
unreal.log("IMPORTED: " + str(paths))
for p in paths:
    a = unreal.EditorAssetLibrary.load_asset(p)
    if isinstance(a, unreal.StaticMesh):
        b = a.get_bounds()
        unreal.log("BOUNDS %s origin=%s extent=%s" % (p, b.origin, b.box_extent))
unreal.SystemLibrary.execute_console_command(None, "QUIT_EDITOR")
