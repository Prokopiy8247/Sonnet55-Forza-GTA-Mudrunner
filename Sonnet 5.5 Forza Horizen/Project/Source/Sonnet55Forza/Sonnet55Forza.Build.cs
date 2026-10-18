// Copyright Epic Games, Inc. All Rights Reserved.

using UnrealBuildTool;

/// <summary>
/// Runtime module of "Roamline: Open Roads".
///
/// MERGE RULE (several agents extend this file in parallel git worktrees): every dependency sits on its OWN line inside
/// the section that matches its purpose, so independent additions merge without conflicts. Do not reflow the lists.
///
/// DESIGN DECISIONS
///  * Headers live next to their .cpp (Core/, Data/, Vehicle/ ... as in Docs/ARCHITECTURE.md section 1), there is no
///    Public/Private split. The module root is therefore published as a public include path so that headers are included
///    as  #include "Core/RoamTypes.h"  by this module, by the editor module and by tests.
///  * We do NOT use the Chaos Vehicles plugin (project-owned raycast/spring vehicle, ARCHITECTURE.md section 4), so the
///    experimental ChaosVehiclesPlugin is intentionally not enabled in the .uproject and not referenced here.
///  * The Chaos core modules are listed as PRIVATE dependencies so the vehicle owner can use the Chaos physics-thread
///    handle returned by FBodyInstance::GetBodyInstanceAsyncPhysicsTickHandle() (see Docs/Tech/BUILD_AND_RUN.md,
///    "Physics stepping"). Chaos headers raise engine-side C4996 deprecation warnings in 5.8; include them ONLY from the
///    .cpp files that really need them so our own translation units stay warning-clean.
/// </summary>
public class Sonnet55Forza : ModuleRules
{
	public Sonnet55Forza(ReadOnlyTargetRules Target) : base(Target)
	{
		PCHUsage = PCHUsageMode.UseExplicitOrSharedPCHs;

		// Publish the module root: "Core/RoamTypes.h" style includes work for dependants (editor module, tests).
		PublicIncludePaths.Add(ModuleDirectory);

		// ------------------------------------------------------------------ public API surface
		// Types used in our public headers (UCLASS bases, delegates, Enhanced Input, UMG/Slate base types, settings).
		PublicDependencyModuleNames.AddRange(new string[]
		{
			"Core",
			"CoreUObject",
			"Engine",
			"InputCore",
			"EnhancedInput",
			"DeveloperSettings",
			"PhysicsCore",
			"AudioMixer",
			"Slate",
			"SlateCore",
		});

		// ------------------------------------------------------------------ private implementation dependencies
		// core / platform
		PrivateDependencyModuleNames.Add("ApplicationCore");
		PrivateDependencyModuleNames.Add("RenderCore");
		PrivateDependencyModuleNames.Add("RHI");
		PrivateDependencyModuleNames.Add("Projects");
		PrivateDependencyModuleNames.Add("AssetRegistry");

		// data / serialisation
		PrivateDependencyModuleNames.Add("Json");
		PrivateDependencyModuleNames.Add("JsonUtilities");
		PrivateDependencyModuleNames.Add("XmlParser");

		// UI
		PrivateDependencyModuleNames.Add("UMG");

		// audio (procedural engine synth: USynthComponent lives in AudioMixer, DSP helpers in SignalProcessing)
		PrivateDependencyModuleNames.Add("SignalProcessing");
		PrivateDependencyModuleNames.Add("AudioExtensions");
		PrivateDependencyModuleNames.Add("AudioMixerCore");

		// physics (project-owned vehicle model; see header comment)
		PrivateDependencyModuleNames.Add("Chaos");
		PrivateDependencyModuleNames.Add("ChaosCore");
		PrivateDependencyModuleNames.Add("ChaosSolverEngine");

		// VFX (plugin "Niagara" is enabled in the .uproject)
		PrivateDependencyModuleNames.Add("Niagara");
		PrivateDependencyModuleNames.Add("NiagaraCore");

		// world / AI / navigation
		PrivateDependencyModuleNames.Add("Landscape");
		PrivateDependencyModuleNames.Add("NavigationSystem");
		PrivateDependencyModuleNames.Add("AIModule");
	}
}
