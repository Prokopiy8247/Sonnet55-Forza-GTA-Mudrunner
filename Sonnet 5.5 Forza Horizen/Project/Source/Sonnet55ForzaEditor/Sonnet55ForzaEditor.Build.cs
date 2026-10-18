// Copyright Epic Games, Inc. All Rights Reserved.

using UnrealBuildTool;

/// <summary>
/// Editor-only module: world builder utilities, data-asset factories and the Python-callable URoamEditorLibrary
/// (Docs/ARCHITECTURE.md sections 1 and 6). Registered in Sonnet55Forza.uproject with "Type": "Editor" and added to the
/// editor target only (Sonnet55ForzaEditor.Target.cs ExtraModuleNames), so it never ships in the game target.
///
/// MERGE RULE: one dependency per line, grouped by purpose, so parallel additions merge cleanly.
/// </summary>
public class Sonnet55ForzaEditor : ModuleRules
{
	public Sonnet55ForzaEditor(ReadOnlyTargetRules Target) : base(Target)
	{
		PCHUsage = PCHUsageMode.UseExplicitOrSharedPCHs;
		PublicIncludePaths.Add(ModuleDirectory);

		PublicDependencyModuleNames.AddRange(new string[]
		{
			"Core",
			"CoreUObject",
			"Engine",
			"PhysicsCore",
			"Sonnet55Forza",
		});

		// editor framework
		PrivateDependencyModuleNames.Add("UnrealEd");
		PrivateDependencyModuleNames.Add("EditorSubsystem");
		PrivateDependencyModuleNames.Add("EditorScriptingUtilities");
		PrivateDependencyModuleNames.Add("LevelEditor");
		PrivateDependencyModuleNames.Add("Slate");
		PrivateDependencyModuleNames.Add("SlateCore");
		PrivateDependencyModuleNames.Add("InputCore");
		PrivateDependencyModuleNames.Add("Projects");

		// assets
		PrivateDependencyModuleNames.Add("AssetTools");
		PrivateDependencyModuleNames.Add("AssetRegistry");
		PrivateDependencyModuleNames.Add("MaterialEditor");

		// terrain / world building
		PrivateDependencyModuleNames.Add("Landscape");
		PrivateDependencyModuleNames.Add("LandscapeEditor");
		PrivateDependencyModuleNames.Add("LandscapeEditorUtilities");

		// scripting
		PrivateDependencyModuleNames.Add("PythonScriptPlugin");

		// data
		PrivateDependencyModuleNames.Add("Json");
		PrivateDependencyModuleNames.Add("JsonUtilities");
	}
}
