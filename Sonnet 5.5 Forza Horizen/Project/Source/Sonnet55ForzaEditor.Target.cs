// Copyright Epic Games, Inc. All Rights Reserved.

using UnrealBuildTool;
using System.Collections.Generic;

public class Sonnet55ForzaEditorTarget : TargetRules
{
	public Sonnet55ForzaEditorTarget( TargetInfo Target) : base(Target)
	{
		Type = TargetType.Editor;
		DefaultBuildSettings = BuildSettingsVersion.V7;
		// Keep in sync with the game target: the include order version decides which engine PCH layout and deprecation
		// behaviour we compile against. Do not lower it.
		IncludeOrderVersion = EngineIncludeOrderVersion.Unreal5_8;
		ExtraModuleNames.Add("Sonnet55Forza");
		// Editor-only tooling module (world builder, data-asset factories, Python-callable library). It is registered in
		// the .uproject with "Type": "Editor", so it is never part of the Game target.
		ExtraModuleNames.Add("Sonnet55ForzaEditor");
	}
}
