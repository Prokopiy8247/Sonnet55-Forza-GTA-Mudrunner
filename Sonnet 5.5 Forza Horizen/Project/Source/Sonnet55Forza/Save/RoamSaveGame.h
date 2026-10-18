// Copyright Epic Games, Inc. All Rights Reserved.

#pragma once

#include "CoreMinimal.h"
#include "GameFramework/SaveGame.h"
#include "Core/RoamTypes.h"
#include "RoamSaveGame.generated.h"

/**
 * The single save-game object of Roamline (slot "Profile", URoamSettings::SaveSlotName). It wraps an FRoamProfile: current car
 * with paint/upgrades/tuning, position, time of day, weather, settings and personal bests.
 *
 * IMPORTANT (engine rule): SaveGameToSlot serialises only properties marked SaveGame - including every member of nested
 * structs. Every property of FRoamProfile and its nested structs therefore carries the SaveGame specifier; new fields must too.
 *
 * Versioning: bump CurrentVersion when a field changes meaning; URoamSaveSubsystem::SanitizeProfile migrates/clamps on load.
 * Unknown/new fields simply load with their default values (tagged property serialisation), so adding fields needs no migration.
 */
UCLASS()
class SONNET55FORZA_API URoamSaveGame : public USaveGame
{
	GENERATED_BODY()

public:
	static constexpr int32 CurrentVersion = 1;

	UPROPERTY(SaveGame)
	int32 Version = CurrentVersion;

	UPROPERTY(SaveGame)
	FRoamProfile Profile;

	/** ISO-8601 UTC timestamp of the last save, informational. */
	UPROPERTY(SaveGame)
	FString SavedAtUtc;
};
