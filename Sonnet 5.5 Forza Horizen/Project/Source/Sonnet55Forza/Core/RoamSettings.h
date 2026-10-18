// Copyright Epic Games, Inc. All Rights Reserved.

#pragma once

#include "CoreMinimal.h"
#include "Engine/DeveloperSettings.h"
#include "Core/RoamTypes.h"
#include "RoamSettings.generated.h"

class ARoamVehicle;
class UPhysicalMaterial;
class URoamCarCatalog;
class URoamRoadNetwork;
class URoamWorldDefinition;

/**
 * Project settings of "Roamline: Open Roads" (Project Settings > Game > Roamline). Stored in Config/DefaultGame.ini under
 * [/Script/Sonnet55Forza.RoamSettings]. All data assets are SOFT references so the game boots (and the empty test map runs)
 * even when the generated world data does not exist yet; every consumer must cope with null.
 *
 * Access:  GetDefault<URoamSettings>()  or the cached accessors on URoamGameInstance (catalog / road network / world).
 */
UCLASS(Config = Game, DefaultConfig, meta = (DisplayName = "Roamline"))
class SONNET55FORZA_API URoamSettings : public UDeveloperSettings
{
	GENERATED_BODY()

public:
	URoamSettings();

	virtual FName GetCategoryName() const override { return TEXT("Game"); }

	// ---- data assets ------------------------------------------------------------------------------------------------
	/** The garage: ordered list of the 10 cars. */
	UPROPERTY(Config, EditAnywhere, Category = "Data", meta = (AllowedClasses = "/Script/Sonnet55Forza.RoamCarCatalog"))
	TSoftObjectPtr<URoamCarCatalog> CarCatalog;

	/** Road graph generated from Tools/world/out/roads.json. */
	UPROPERTY(Config, EditAnywhere, Category = "Data", meta = (AllowedClasses = "/Script/Sonnet55Forza.RoamRoadNetwork"))
	TSoftObjectPtr<URoamRoadNetwork> RoadNetwork;

	/** Regions, POIs, teleport targets and activity placement. */
	UPROPERTY(Config, EditAnywhere, Category = "Data", meta = (AllowedClasses = "/Script/Sonnet55Forza.RoamWorldDefinition"))
	TSoftObjectPtr<URoamWorldDefinition> WorldDefinition;

	// ---- spawning ---------------------------------------------------------------------------------------------------
	/** Pawn class spawned for the player car (ARoamVehicle or a subclass). Empty = ARoamVehicle. */
	UPROPERTY(Config, EditAnywhere, Category = "Spawn", meta = (MetaClass = "/Script/Sonnet55Forza.RoamVehicle"))
	TSoftClassPtr<ARoamVehicle> DefaultVehicleClass;

	/** CarId used on a fresh profile. Empty = first car of the catalog. */
	UPROPERTY(Config, EditAnywhere, Category = "Spawn")
	FName DefaultCarId;

	/** Roads tried in order for the first-launch spawn (a long scenic road). Spawn point = DefaultSpawnS on the first road that exists. */
	UPROPERTY(Config, EditAnywhere, Category = "Spawn")
	TArray<FName> DefaultSpawnRoadIds;

	/** Distance along the spawn road in cm. */
	UPROPERTY(Config, EditAnywhere, Category = "Spawn", meta = (ClampMin = "0.0"))
	float DefaultSpawnS = 20000.0f;

	/** Lane (signed index, see URoamRoadNetwork) the spawn uses; +1 = right-hand lane in the direction of the road. */
	UPROPERTY(Config, EditAnywhere, Category = "Spawn")
	int32 DefaultSpawnLane = 1;

	/** Height above the road/ground at which the car is dropped, cm. */
	UPROPERTY(Config, EditAnywhere, Category = "Spawn", meta = (ClampMin = "0.0"))
	float SpawnDropHeightCm = 60.0f;

	/** Restore the saved transform of the previous session when the profile has one. */
	UPROPERTY(Config, EditAnywhere, Category = "Spawn")
	bool bRestoreSavedTransform = true;

	// ---- time / weather defaults ------------------------------------------------------------------------------------
	UPROPERTY(Config, EditAnywhere, Category = "TimeWeather", meta = (ClampMin = "0.0", ClampMax = "24.0"))
	float DefaultGameHour = 10.0f;

	UPROPERTY(Config, EditAnywhere, Category = "TimeWeather")
	ERoamWeather DefaultWeather = ERoamWeather::Clear;

	/** Game seconds per real second. 30 = one game hour per two real minutes. 0 freezes time. */
	UPROPERTY(Config, EditAnywhere, Category = "TimeWeather", meta = (ClampMin = "0.0", ClampMax = "2000.0"))
	float DefaultTimeScale = 30.0f;

	/** Let the weather change on its own (randomised dwell times). */
	UPROPERTY(Config, EditAnywhere, Category = "TimeWeather")
	bool bAutoWeather = false;

	/** Day of the year used by the sun model (172 = June solstice, 80 = spring equinox). */
	UPROPERTY(Config, EditAnywhere, Category = "TimeWeather", meta = (ClampMin = "1", ClampMax = "365"))
	int32 SunDayOfYear = 172;

	/** Latitude used by the sun model when no world definition provides one. */
	UPROPERTY(Config, EditAnywhere, Category = "TimeWeather")
	float SunLatitudeDeg = 36.0f;

	// ---- profile / save ---------------------------------------------------------------------------------------------
	UPROPERTY(Config, EditAnywhere, Category = "Save")
	FString SaveSlotName = TEXT("Profile");

	UPROPERTY(Config, EditAnywhere, Category = "Save")
	bool bAutoLoadProfile = true;

	// ---- surfaces ---------------------------------------------------------------------------------------------------
	/**
	 * Optional overrides: physical material asset -> Roamline surface. Normal case: the physical material's SurfaceType
	 * (SurfaceType1..8, set by Tools/ue scripts) is mapped 1:1 by Roam::SurfaceFromPhysicalSurface and this map stays empty.
	 */
	UPROPERTY(Config, EditAnywhere, Category = "Surfaces")
	TMap<TSoftObjectPtr<UPhysicalMaterial>, ERoamSurface> PhysicalMaterialToSurface;

	// ---- developer --------------------------------------------------------------------------------------------------
	/** Draw the one-line debug text (car / speed / gear) on the canvas HUD shell until the Slate HUD replaces it. */
	UPROPERTY(Config, EditAnywhere, Category = "Developer")
	bool bShowHudShellDebugText = true;

	/** Resolves a physical material to a surface: override map first, then SurfaceType mapping. nullptr -> Asphalt. */
	ERoamSurface ResolveSurface(const UPhysicalMaterial* PhysicalMaterial) const;

	/** The player vehicle class (loads the soft class; falls back to ARoamVehicle). */
	TSubclassOf<ARoamVehicle> LoadVehicleClass() const;
};
