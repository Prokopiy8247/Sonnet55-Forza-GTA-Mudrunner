import unreal
FBX = unreal.Paths.project_dir() + "Exports/Test/PT_Wheel_Centered.fbx"
task = unreal.AssetImportTask()
task.set_editor_property("filename", FBX)
task.set_editor_property("destination_path", "/Game/Forza/Test3")
task.set_editor_property("automated", True)
task.set_editor_property("replace_existing", True)
task.set_editor_property("save", True)
unreal.AssetToolsHelpers.get_asset_tools().import_asset_tasks([task])
for p in list(task.get_editor_property("imported_object_paths")):
    a = unreal.EditorAssetLibrary.load_asset(p)
    if isinstance(a, unreal.StaticMesh):
        b = a.get_bounds()
        unreal.log("BOUNDS3 %s origin=(%.1f,%.1f,%.1f) extent=(%.1f,%.1f,%.1f)" % (p, b.origin.x, b.origin.y, b.origin.z, b.box_extent.x, b.box_extent.y, b.box_extent.z))
unreal.SystemLibrary.execute_console_command(None, "QUIT_EDITOR")
