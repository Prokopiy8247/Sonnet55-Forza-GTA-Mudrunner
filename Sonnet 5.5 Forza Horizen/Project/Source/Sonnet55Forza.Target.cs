// Copyright Epic Games, Inc. All Rights Reserved.

using UnrealBuildTool;
using System.Collections.Generic;

public class Sonnet55ForzaTarget : TargetRules
{
	public Sonnet55ForzaTarget(TargetInfo Target) : base(Target)
	{
		Type = TargetType.Game;
		DefaultBuildSettings = BuildSettingsVersion.V7;
		IncludeOrderVersion = EngineIncludeOrderVersion.Unreal5_8;
		// Runtime module only. The Sonnet55ForzaEditor module is deliberately NOT listed here.
		ExtraModuleNames.Add("Sonnet55Forza");
	}
}
