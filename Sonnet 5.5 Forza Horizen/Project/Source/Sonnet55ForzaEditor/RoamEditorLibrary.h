// Copyright Epic Games, Inc. All Rights Reserved.

#pragma once

#include "CoreMinimal.h"
#include "Kismet/BlueprintFunctionLibrary.h"
#include "RoamEditorLibrary.generated.h"

class AGameModeBase;
class UPhysicalMaterial;
class UPrimitiveComponent;
class UWorld;

/**
 * Editor-only static helpers, callable from Python as  unreal.RoamEditorLibrary.<snake_case_name>(...).
 *
 * Purpose: everything the Python editor API cannot express (or expresses clumsily) lives here, so the Tools/ue/*.py scripts
 * stay thin and re-runnable (Docs/ARCHITECTURE.md section 6). The world-builder agent extends this class in its own
 * file region (keep functions independent; do not reorder existing ones).
 */
UCLASS()
class URoamEditorLibrary : public UBlueprintFunctionLibrary
{
	GENERATED_BODY()

public:
	/** Trivial smoke function proving the editor module loaded and is reachable from Python. Returns e.g. "RoamEditorLibrary OK (UE 5.8.2)". */
	UFUNCTION(BlueprintCallable, Category = "Roam|Editor")
	static FString GetRoamEditorLibraryStatus();

	/** Adds two numbers; exists so the Python smoke test can verify argument marshalling and return values. */
	UFUNCTION(BlueprintCallable, Category = "Roam|Editor")
	static int32 SmokeAdd(int32 A, int32 B);

	/** Sets the GameMode override of a level's world settings. Returns false if World/GameModeClass is null. */
	UFUNCTION(BlueprintCallable, Category = "Roam|Editor")
	static bool SetWorldGameModeOverride(UWorld* World, TSubclassOf<AGameModeBase> GameModeClass);

	/** Assigns a physical material override to a primitive component's body instance (marks the owner dirty). */
	UFUNCTION(BlueprintCallable, Category = "Roam|Editor")
	static bool SetComponentPhysicalMaterial(UPrimitiveComponent* Component, UPhysicalMaterial* PhysicalMaterial);

	/** Sets the surface type (SurfaceType1..8 via ERoamSurface index 0..7) and friction of a physical material asset. */
	UFUNCTION(BlueprintCallable, Category = "Roam|Editor")
	static bool ConfigureRoamPhysicalMaterial(UPhysicalMaterial* PhysicalMaterial, int32 RoamSurfaceIndex, float Friction, float StaticFriction, float Density);

	/** Dumps URoamSettings (configured data asset references) to the log; returns a one-line summary. */
	UFUNCTION(BlueprintCallable, Category = "Roam|Editor")
	static FString DescribeRoamSettings();
};
