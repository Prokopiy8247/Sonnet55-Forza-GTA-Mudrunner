// Copyright Epic Games, Inc. All Rights Reserved.

#pragma once

#include "CoreMinimal.h"
#include "Engine/DataAsset.h"
#include "RoamWorldDefinition.generated.h"

/**
 * Data of the open world that gameplay systems need at runtime: regions, points of interest, teleport targets and the
 * activity placement list. Built by the editor module from Tools/world/worlddef.py + roads.json (Docs/WORLD_SPEC.md) and
 * referenced from URoamSettings::WorldDefinition. All positions are UE world cm (the generator converts from metres).
 *
 * Consumers: URoamRegionSubsystem (region lookup, popups, `tp`), URoamActivitySubsystem (activity list), URoamUISubsystem
 * (map/minimap icons), URoamTrafficSubsystem (density scale per region), console commands (`tp <region|poi>`).
 */

UENUM(BlueprintType)
enum class ERoamPoiType : uint8
{
	Settlement = 0,
	GasStation,
	Diner,
	Viewpoint,
	Landmark,
	Tunnel,
	Bridge,
	RoadStart,     // start point of a long scenic road (benchmark teleport target)
	Garage,
	Other
};

UENUM(BlueprintType)
enum class ERoamActivityType : uint8
{
	SpeedTrap = 0,
	SpeedZone,
	DriftZone,
	DangerSign,
	CheckpointRace,
	TimeTrial,
	Collectible,
	PhotoSpot
};

/** An axis-aligned rectangle of the world with a name. Higher Priority wins where regions overlap (hub on top). */
USTRUCT(BlueprintType)
struct SONNET55FORZA_API FRoamRegionDef
{
	GENERATED_BODY()

	/** "greenvale", "highcrest", "sunbaked", "saltcliff", "crossroads" (Docs/WORLD_SPEC.md section 2). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Region")
	FName RegionId;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Region")
	FText DisplayName;

	/** Second line of the region popup. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Region")
	FText Subtitle;

	/** XY bounds in UE cm. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Region")
	FVector2D MinXY = FVector2D::ZeroVector;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Region")
	FVector2D MaxXY = FVector2D::ZeroVector;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Region")
	int32 Priority = 0;

	/** Colour on the map. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Region")
	FLinearColor MapColor = FLinearColor::White;

	/** Climate zone key used by the weather system ("Coast", "Valley", "DryHills", "Mountain"). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Region")
	FName ClimateZone;

	/** Multiplies the traffic density inside the region. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Region")
	float TrafficDensityScale = 1.0f;

	bool Contains(const FVector& WorldLocation) const
	{
		return WorldLocation.X >= MinXY.X && WorldLocation.X <= MaxXY.X && WorldLocation.Y >= MinXY.Y && WorldLocation.Y <= MaxXY.Y;
	}
};

/** Point of interest / teleport target. */
USTRUCT(BlueprintType)
struct SONNET55FORZA_API FRoamPoiDef
{
	GENERATED_BODY()

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "POI")
	FName PoiId;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "POI")
	FText DisplayName;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "POI")
	ERoamPoiType Type = ERoamPoiType::Other;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "POI")
	FVector Location = FVector::ZeroVector;

	/** Heading the car faces after a teleport (degrees, world yaw). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "POI")
	float YawDeg = 0.0f;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "POI")
	FName RegionId;

	/** Appears in `tp` and in the debug menu. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "POI")
	bool bTeleportTarget = true;

	/** Road the POI sits on (for road-aligned teleports); NAME_None if free-standing. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "POI")
	FName RoadId;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "POI")
	float RoadS = 0.0f;
};

/** A gate for segment-vs-plane crossing tests (activities never use overlap volumes, see Docs/Tech/FH5_activities.md 2.3). */
USTRUCT(BlueprintType)
struct SONNET55FORZA_API FRoamGate
{
	GENERATED_BODY()

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Gate")
	FVector Center = FVector::ZeroVector;

	/** Unit vector normal to the gate plane (direction of the allowed crossing). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Gate")
	FVector Forward = FVector::ForwardVector;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Gate")
	float HalfWidthCm = 600.0f;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Gate")
	float HalfHeightCm = 400.0f;
};

/**
 * Static description of one activity. The activity subsystem turns it into runtime state; visuals (ARoamActivityActor
 * subclasses) are placed from the same list by the world builder. Thresholds hold the three star values (1, 2, 3 stars).
 */
USTRUCT(BlueprintType)
struct SONNET55FORZA_API FRoamActivityDef
{
	GENERATED_BODY()

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Activity")
	FName ActivityId;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Activity")
	ERoamActivityType Type = ERoamActivityType::SpeedTrap;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Activity")
	FText DisplayName;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Activity")
	FName RegionId;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Activity")
	FName RoadId;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Activity")
	float RoadS = 0.0f;

	/** Start, end and intermediate gates in driving order (speed trap: 1 gate, zones/jumps: start+end, races: all checkpoints). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Activity")
	TArray<FRoamGate> Gates;

	/** Route polyline (cm, 5 m spacing) for zones, sprints and races; empty for gate-only activities. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Activity")
	TArray<FVector> RoutePoints;

	/** Thresholds for 1, 2, 3 stars (km/h, points, metres or seconds depending on Type). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Activity")
	FVector StarThresholds = FVector::ZeroVector;

	/** True for time-based activities where a LOWER value is better (races, time trials). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Activity")
	bool bLowerIsBetter = false;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Activity")
	int32 XpReward = 100;

	/** Type specific numbers (ramp lip box size, drift min angle, ...). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Activity")
	TMap<FName, float> Params;
};

UCLASS(BlueprintType)
class SONNET55FORZA_API URoamWorldDefinition : public UDataAsset
{
	GENERATED_BODY()

public:
	/** World extent for the map / minimap underlay (UE cm, XY). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "World")
	FVector2D MapMinXY = FVector2D(-201600.0, -201600.0);
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "World")
	FVector2D MapMaxXY = FVector2D(201600.0, 201600.0);

	/** Sea level in cm. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "World")
	float SeaLevelCm = 0.0f;

	/** Latitude used by the sun model (degrees north). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "World")
	float LatitudeDeg = 36.0f;

	/** POI id the game starts at when no saved transform exists (NAME_None: URoamSettings default spawn road). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "World")
	FName DefaultSpawnPoi;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "World")
	TArray<FRoamRegionDef> Regions;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "World")
	TArray<FRoamPoiDef> Pois;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "World")
	TArray<FRoamActivityDef> Activities;

	/** Highest-priority region containing the location, or nullptr. */
	const FRoamRegionDef* FindRegionAt(const FVector& WorldLocation) const;
	const FRoamRegionDef* FindRegion(FName RegionId) const;
	const FRoamPoiDef* FindPoi(FName PoiId) const;
	const FRoamActivityDef* FindActivity(FName ActivityId) const;

	/**
	 * Resolves user text for `tp <region|poi>`: exact id or display name first, then unique prefix/substring among POIs and
	 * regions. A region resolves to its centre (OutLocation.Z = 0, caller drops to ground); a POI to its location/yaw.
	 */
	bool ResolveTeleportTarget(const FString& Text, FVector& OutLocation, float& OutYawDeg, FString* OutLabel = nullptr, FString* OutError = nullptr) const;
};
