// Copyright Epic Games, Inc. All Rights Reserved.

#pragma once

#include "CoreMinimal.h"
#include "Core/RoamTypes.h"

class URoamRoadNetwork;

/**
 * One directed lane of the traffic lane graph: the centreline of lane LaneIndex of a road, resampled every StepCm in the direction of
 * travel (so index i is at travel distance i * StepCm; the last point is at LengthCm exactly). Right-hand traffic comes from the road
 * network lane convention (positive indices run along increasing S on the right of the centreline).
 */
struct SONNET55FORZA_API FRoamLane
{
	int32 RoadIndex = INDEX_NONE;
	int32 LaneIndex = 0; // signed, as in the road network
	bool bForward = true; // travels along increasing road S
	ERoamRoadClass RoadClass = ERoamRoadClass::Regional;
	ERoamSurface Surface = ERoamSurface::Asphalt;
	float LengthCm = 0.0f;
	float StepCm = 500.0f;
	float SpeedLimitMs = 22.0f;
	/** Number of lanes of the road in this direction (density is given per km per direction). */
	int32 LanesInDirection = 1;

	/** Network junction indices at the travel start / end (INDEX_NONE = dead end). */
	int32 StartJunction = INDEX_NONE;
	int32 EndJunction = INDEX_NONE;
	/** Length of the junction connector on this lane (the Bezier blend into / out of the junction). 0 without a junction. */
	float BlendStartCm = 0.0f;
	float BlendEndCm = 0.0f;
	/** Priority of the junction arm this lane arrives on (FRoamJunctionArm::Priority). */
	int32 EndArmPriority = 0;
	/** Identifies the arrival arm (road end) at the end junction: RoadIndex * 2 + (bForward ? 1 : 0). */
	int32 ArmKey = 0;

	TArray<FVector> Points;
	TArray<FVector> Dirs; // unit travel direction per point
	TArray<float> CurvaturePerCm; // |curvature| per point (1/cm), clamped to a 15 m radius

	/** Lanes that continue this lane through the end junction (no U-turns), with choice weight and turn angle (radians). */
	TArray<int32> Successors;
	TArray<float> SuccessorWeight;
	TArray<float> SuccessorTurnRad;

	void Sample(float S, FVector& OutPos, FVector& OutDir) const;
	float CurvatureAt(float S) const;
};

/** Directed lane graph + spatial hash of lane points, built from a URoamRoadNetwork. No UObject, usable from tests. */
struct SONNET55FORZA_API FRoamLaneGraph
{
	struct FCellEntry
	{
		int32 Lane = 0;
		int32 Point = 0;
	};

	TArray<FRoamLane> Lanes;
	TArray<FVector> JunctionPos;
	TArray<float> JunctionRadius;
	TArray<ERoamJunctionControl> JunctionControl;
	float TotalLaneLengthCm = 0.0f;

	void Reset();
	void Build(const URoamRoadNetwork& Network, float StepCm = 500.0f);
	bool IsEmpty() const { return Lanes.Num() == 0; }

	/** Visits every lane point whose XY distance to Center is <= RadiusCm (cheap broad phase: grid cells, then exact test). */
	void ForEachPointInRadius(const FVector& Center, float RadiusCm, TFunctionRef<void(int32 /*Lane*/, int32 /*Point*/, const FVector& /*Position*/)> Visitor) const;

	/** Lane whose point is closest to Location (XY), searching within MaxDistanceCm. Returns INDEX_NONE if none. */
	int32 FindNearestLane(const FVector& Location, float MaxDistanceCm, float* OutS = nullptr, float* OutDistanceCm = nullptr) const;

private:
	static constexpr float CellSizeCm = 20000.0f;
	TMap<FIntPoint, TArray<FCellEntry>> Cells;
	static FIntPoint CellOf(const FVector& P);
};
