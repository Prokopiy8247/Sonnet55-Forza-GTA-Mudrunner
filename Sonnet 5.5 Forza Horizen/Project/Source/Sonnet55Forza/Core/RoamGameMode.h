// Copyright Epic Games, Inc. All Rights Reserved.

#pragma once

#include "CoreMinimal.h"
#include "GameFramework/GameModeBase.h"
#include "RoamGameMode.generated.h"

class ARoamVehicle;
class URoamCarDefinition;

/** Where the start transform of the player came from (logged as ROAM_SPAWN source=...). */
UENUM(BlueprintType)
enum class ERoamSpawnSource : uint8
{
	SavedTransform = 0,
	RoadNetwork,
	WorldPoi,
	PlayerStart,
	Origin
};

/**
 * Game mode of free roam (Config/DefaultEngine.ini GlobalDefaultGameMode, also set as GameMode override of the maps).
 * It spawns the player's car instead of a default pawn:
 *
 *   start transform, first match wins:
 *     1. the transform of the saved profile (URoamSettings::bRestoreSavedTransform),
 *     2. the default POI of the world definition (URoamWorldDefinition::DefaultSpawnPoi),
 *     3. the first existing road of URoamSettings::DefaultSpawnRoadIds at DefaultSpawnS in lane DefaultSpawnLane, facing the lane direction,
 *     4. a PlayerStart of the level,
 *     5. the world origin.
 *   The position is dropped onto the ground with a trace on the wheel channel (SpawnDropHeightCm above it).
 *
 *   car: the profile's CarId, else URoamSettings::DefaultCarId, else the first car of the catalog, else the placeholder look.
 *
 * It also owns the car-switch API used by the console / garage / debug menu: SpawnPlayerCar(CarId, Transform).
 * Console commands registered in RoamGameMode.cpp: cars, car, respawn, reset, flip, paint, assist, camera.
 */
UCLASS()
class SONNET55FORZA_API ARoamGameMode : public AGameModeBase
{
	GENERATED_BODY()

public:
	ARoamGameMode();

	//~ Begin AGameModeBase
	virtual void StartPlay() override;
	virtual void RestartPlayer(AController* NewPlayer) override;
	virtual UClass* GetDefaultPawnClassForController_Implementation(AController* InController) override;
	virtual APawn* SpawnDefaultPawnAtTransform_Implementation(AController* NewPlayer, const FTransform& SpawnTransform) override;
	//~ End

	/**
	 * Replaces the player's car by another one at the given transform (the old pawn is destroyed, the new one possessed).
	 * CarId may be an exact id or anything URoamCarCatalog::ResolveCar understands. Returns the new vehicle or nullptr.
	 */
	UFUNCTION(BlueprintCallable, Category = "Roam|GameMode")
	ARoamVehicle* SpawnPlayerCar(FName CarId, const FTransform& Transform);

	/** Same, at the current transform of the player's car (a little lifted, speed zero). */
	UFUNCTION(BlueprintCallable, Category = "Roam|GameMode")
	ARoamVehicle* SpawnPlayerCarAtCurrent(FName CarId);

	/** Resolves the car the player should drive now (profile > settings default > first catalog car). May return nullptr. */
	URoamCarDefinition* ResolveCarDefinition(FName RequestedCarId = NAME_None) const;

	/** Start transform of the player (see class comment). */
	FTransform ComputeSpawnTransform(ERoamSpawnSource& OutSource) const;

	/** Drops a transform onto the ground below it (wheel channel trace); keeps the input Z if nothing is hit. */
	FTransform DropToGround(const FTransform& Transform) const;

	/**
	 * Highways carry a 0.8 m New-Jersey barrier in their median and world data (POIs, spawn points) sits on the road centreline: a car
	 * dropped there lands on the barrier. When the transform is within ~1.5 m of a HIGHWAY centreline this moves it into the forward lane
	 * that matches its heading (XY and a little above the road surface). Returns true when it was moved. No road network = no change.
	 */
	static bool SnapOffMedian(const UObject* WorldContext, FTransform& InOutTransform);

	/** Current game mode if it is an ARoamGameMode. */
	static ARoamGameMode* Get(const UObject* WorldContext);

private:
	ARoamVehicle* SpawnVehicle(URoamCarDefinition* Definition, const FTransform& Transform);
};
