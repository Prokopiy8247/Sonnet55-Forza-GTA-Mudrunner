// Copyright Epic Games, Inc. All Rights Reserved.

#pragma once

#include "CoreMinimal.h"
#include "Engine/DataAsset.h"
#include "Core/RoamTypes.h"
#include "RoamRoadNetwork.generated.h"

/**
 * The drivable road graph: roads (centreline polylines), junctions, a spatial grid for nearest-road queries and an A*
 * router on the junction graph (Docs/ARCHITECTURE.md section 3, Docs/WORLD_SPEC.md section 3).
 *
 * DATA CONTRACT (for the generator in Tools/world and the editor importer):
 *  - Roads are split at junctions: a road starts and ends at a junction (StartJunction / EndJunction) or at a dead end
 *    (NAME_None). No two roads cross except at a junction, or one passes over the other on a bridge (use MaxVerticalCm).
 *  - Samples are ~5 m apart, positions in UE world cm. S (cumulative length) and LengthCm are recomputed here.
 *  - LANE CONVENTION: LaneIndex is signed. +1..+LanesForward are the lanes carrying traffic in the direction of increasing S
 *    (+1 nearest the centreline); -1..-LanesBackward carry traffic against it (-1 nearest the centreline). With
 *    bRightHandTraffic the forward lanes lie on the RIGHT of the centreline (positive lateral offset along Right).
 *
 * The asset is read-only at runtime. Consumers: traffic (lane graph), activities (route progress), UI (minimap polylines,
 * GPS route), game mode (spawn on road), vehicle (ResetToRoad), time/weather (surface lookup).
 */
UCLASS(BlueprintType)
class SONNET55FORZA_API URoamRoadNetwork : public UDataAsset
{
	GENERATED_BODY()

public:
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Network")
	TArray<FRoamRoad> Roads;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Network")
	TArray<FRoamJunction> Junctions;

	/** Edge length of a spatial-grid cell in cm (nearest queries touch ~9 cells). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Network", meta = (ClampMin = "2000.0"))
	float GridCellSizeCm = 20000.0f;

	/** Traffic keeps right (lanes with positive index lie on the right of the centreline). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Network")
	bool bRightHandTraffic = true;

	// ---- lifecycle -------------------------------------------------------------------------------------------------

	/**
	 * Recomputes S/LengthCm/tangents, the id lookup tables, the spatial grid and the junction adjacency. Called from
	 * PostLoad; call it manually after filling Roads/Junctions in code (importer, tests).
	 */
	UFUNCTION(BlueprintCallable, Category = "Roam|Roads")
	void BuildSpatialIndex();

	bool IsIndexBuilt() const { return bIndexBuilt; }

	//~ Begin UObject
	virtual void PostLoad() override;
#if WITH_EDITOR
	virtual void PostEditChangeProperty(FPropertyChangedEvent& PropertyChangedEvent) override;
#endif
	//~ End UObject

	// ---- lookup ----------------------------------------------------------------------------------------------------
	UFUNCTION(BlueprintCallable, Category = "Roam|Roads")
	int32 FindRoadIndex(FName RoadId) const;
	UFUNCTION(BlueprintCallable, Category = "Roam|Roads")
	int32 FindJunctionIndex(FName JunctionId) const;
	const FRoamRoad* FindRoad(FName RoadId) const;
	const FRoamJunction* FindJunction(FName JunctionId) const;
	int32 GetNumRoads() const { return Roads.Num(); }
	UFUNCTION(BlueprintCallable, Category = "Roam|Roads")
	float GetTotalLengthCm() const;

	// ---- queries ---------------------------------------------------------------------------------------------------

	/** Nearest road point to Query.Location (see FRoamRoadQuery for filters). Returns false if no road is within range. */
	bool FindNearest(const FRoamRoadQuery& Query, FRoamRoadHit& OutHit) const;

	UFUNCTION(BlueprintCallable, Category = "Roam|Roads")
	bool FindNearestRoad(FVector Location, FRoamRoadHit& OutHit, int32 ClassMask = 0xFF, float MaxDistanceCm = 50000.0f) const;

	/**
	 * Fast incremental projection onto ONE road around a previous S (for per-frame tracking, e.g. activity progress):
	 * only segments within HintS +- WindowCm are tested. HintS < 0 searches the whole road.
	 */
	bool FindNearestOnRoad(int32 RoadIndex, const FVector& Location, float HintS, float WindowCm, FRoamRoadHit& OutHit) const;

	/** Centreline sample at distance S (clamped to the road) as a hit (Position/Tangent/Right/Surface/width/limit). */
	UFUNCTION(BlueprintCallable, Category = "Roam|Roads")
	bool SamplePosition(FName RoadId, float S, FRoamRoadHit& OutHit) const;
	bool SamplePositionByIndex(int32 RoadIndex, float S, FRoamRoadHit& OutHit) const;

	/** Interpolated sample (position, tangent, bank, width, flags) of a road; S is clamped. The road needs >= 2 samples. */
	static FRoamRoadSample SampleRoad(const FRoamRoad& Road, float S);

	/** Signed lateral offset in cm of the centre of a lane (see the lane convention above). LaneIndex 0 returns 0. */
	float LaneOffsetCm(const FRoamRoad& Road, int32 LaneIndex) const;

	/** World position of the centre of a lane at the hit's S. */
	FVector GetLanePosition(const FRoamRoadHit& Hit, int32 LaneIndex) const;

	/** Direction of travel of a lane at the hit (Tangent for forward lanes, -Tangent for backward lanes). */
	static FVector GetLaneDirection(const FRoamRoadHit& Hit, int32 LaneIndex);

	/** Lane (signed index) whose centre is closest to Location, given a hit from FindNearest. 0 if the road has no lanes. */
	int32 FindClosestLane(const FRoamRoadHit& Hit) const;

	/** Speed limit in km/h of the road under a hit. */
	static float GetSpeedLimitKmh(const FRoamRoadHit& Hit) { return Hit.SpeedLimitKmh; }

	// ---- routing ---------------------------------------------------------------------------------------------------

	/** Relative cost per cm for a road class (highway 1.0, regional 1.25, mountain 1.8, dirt/shortcut 2.5, village 1.4). */
	static float GetRouteCostFactor(ERoamRoadClass RoadClass);

	/** A* between two world locations (each projected onto its nearest road). */
	bool FindRoute(const FVector& From, const FVector& To, FRoamRoute& OutRoute) const;

	/** A* between two road hits. */
	bool FindRouteBetween(const FRoamRoadHit& From, const FRoamRoadHit& To, FRoamRoute& OutRoute) const;

	/** Samples a route into a polyline (points every SpacingCm along the legs). */
	void BuildRoutePolyline(const FRoamRoute& Route, float SpacingCm, TArray<FVector>& OutPoints) const;

	// ---- validation / testing --------------------------------------------------------------------------------------

	/** Consistency checks (ids unique, samples >= 2, junction references resolve, arms point to existing roads). */
	bool Validate(TArray<FString>& OutProblems) const;

	/**
	 * Builds a synthetic network in memory for unit tests and for running without generated world data:
	 * a JunctionsPerSide x JunctionsPerSide grid of junctions SpacingCm apart centred on the origin, straight roads between
	 * neighbours (middle row = Highway, others Regional) plus one Dirt diagonal from the first to the last junction.
	 * Road ids: "H_<row>_<col>", "V_<col>_<row>", "D_diag"; junction ids "J_<col>_<row>" (col along +X, row along +Y).
	 */
	static URoamRoadNetwork* BuildGeneratedForTests(UObject* Outer, int32 JunctionsPerSide = 3, float SpacingCm = 100000.0f, float SampleSpacingCm = 500.0f);

private:
	struct FGridEntry
	{
		int32 RoadIndex = 0;
		int32 SegmentIndex = 0;
	};

	struct FJunctionEdge
	{
		int32 ToJunction = INDEX_NONE;
		int32 RoadIndex = INDEX_NONE;
		bool bForward = true; // true: road start -> end
		float LengthCm = 0.0f;
		float Cost = 0.0f;
	};

	FIntPoint CellOf(const FVector& Location) const;
	void FillHit(int32 RoadIndex, int32 SegmentIndex, float Alpha, const FVector& QueryLocation, FRoamRoadHit& OutHit) const;
	void TestSegment(int32 RoadIndex, int32 SegmentIndex, const FRoamRoadQuery& Query, float& InOutBestScore, FRoamRoadHit& OutHit, bool& bFound) const;

	bool bIndexBuilt = false;
	TMap<FName, int32> RoadIndexById;
	TMap<FName, int32> JunctionIndexById;
	TMap<FIntPoint, TArray<FGridEntry>> Grid;
	TArray<TArray<FJunctionEdge>> Adjacency;
};
