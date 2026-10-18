import unreal
unreal.log("HELLO_FROM_PYTHON engine=" + unreal.SystemLibrary.get_engine_version())
unreal.log("PROJECT_DIR=" + unreal.Paths.project_dir())
unreal.log("HAS_LANDSCAPE_EDITOR_UTILS=" + str(hasattr(unreal, "LandscapeEditorUtils")))
unreal.log("HAS_EDITOR_ASSET_LIB=" + str(hasattr(unreal, "EditorAssetLibrary")))
unreal.log("HAS_INTERCHANGE_MANAGER=" + str(hasattr(unreal, "InterchangeManager")))
unreal.log("HAS_WP_LIB=" + str(hasattr(unreal, "WorldPartitionBlueprintLibrary")))
unreal.SystemLibrary.execute_console_command(None, "QUIT_EDITOR")
