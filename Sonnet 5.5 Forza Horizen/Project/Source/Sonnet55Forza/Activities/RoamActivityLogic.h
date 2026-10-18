// Copyright Epic Games, Inc. All Rights Reserved.

#pragma once

#include "CoreMinimal.h"
#include "Data/RoamWorldDefinition.h"

class URoamRoadNetwork;

/**
 * Pure (world-free, UObject-free) helpers of the activity system, so they can be unit tested without a game world:
 * gate crossing with sub-frame interpolation, star mapping, threshold generation from the Docs/Tech/FH5_activities.md formulas,
 * the drift score state machine and the default placement of activities on a road network.
 */
namespace RoamActivity
{
	// ---- gates -----------------------------------------------------------------------------------------------------
	struct FGateCrossing
	{
		/** 0..1 position of the crossing inside the tested segment A->B (sub-frame time / speed interpolation). */
		float Alpha = 0.0f;
		FVector Point = FVector::ZeroVector;
		/** Lateral offset of the crossing point from the gate centre (+ = right of the gate direction). */
		float LateralCm = 0.0f;
		/** True when the segment crossed in the direction of Gate.Forward. */
		bool bForward = true;
	};

	/**
	 * Segment A->B vs the gate rectangle (centre, normal Forward, half width along Right = Up x Forward, half height along Z).
	 * Only crossings in the direction of Forward count unless bAllowReverse. A segment that starts exactly on the plane counts
	 * through the PREVIOUS segment (dB >= 0 is the inclusive side), so a crossing is never reported twice.
	 */
	SONNET55FORZA_API bool SegmentCrossesGate(const FRoamGate& Gate, const FVector& A, const FVector& B, FGateCrossing& Out, bool bAllowReverse = false);

	// ---- stars / thresholds -----------------------------------------------------------------------------------------
	SONNET55FORZA_API float RoundTo(float Value, float Step);
	/** Thresholds are (1 star, 2 stars, 3 stars). Higher-is-better: value >= threshold. Lower-is-better (times): value <= threshold. */
	SONNET55FORZA_API int32 StarsForValue(const FVector& Thresholds, float Value, bool bLowerIsBetter);

	/** Speed trap: 0.28 / 0.69 / 1.0 x V3 rounded to 5 km/h. */
	SONNET55FORZA_API FVector SpeedTrapThresholds(float V3Kmh);
	/** Speed zone (average): 0.38 / 0.74 / 1.0 x V3 rounded to 5 km/h. */
	SONNET55FORZA_API FVector SpeedZoneThresholds(float V3Kmh);
	/** Drift zone: 0.08 / 0.53 / 1.0 x S3 (S3 rounded to 2500, never below 2500). */
	SONNET55FORZA_API FVector DriftThresholds(float S3);
	/** Jump: 0.20 / 0.55 / 1.0 x D3 rounded to 5 m. */
	SONNET55FORZA_API FVector JumpThresholds(float D3Metres);
	/** Races / time trials: allowances in seconds (bronze 1.50, silver 1.30, gold 1.15 x profile time x class factor). X >= Y >= Z. */
	SONNET55FORZA_API FVector TimeThresholds(float ProfileSeconds, float ClassFactor);

	/** "m:ss.cc" */
	SONNET55FORZA_API FString FormatTime(float Seconds);

	/** Own palette per activity type (gate tint and HUD accent). */
	SONNET55FORZA_API FLinearColor TypeColor(ERoamActivityType Type);
	/** Upper-case HUD title ("SPEED TRAP", "DANGER SIGN" ...). */
	SONNET55FORZA_API FString TypeTitle(ERoamActivityType Type);

	/** XP of a stunt: pays star improvements {0,100,250,500} plus 50 on the first clear, scaled by XpReward/100. */
	SONNET55FORZA_API int32 XpForStarImprovement(int32 OldStars, int32 NewStars, int32 XpReward);

	// ---- drift score (Docs/Tech/FH5_activities.md 4.3) ---------------------------------------------------------------
	struct SONNET55FORZA_API FDriftTracker
	{
		float MinSpeedKmh = 30.0f;
		float EnterAngleDeg = 12.0f;
		float KeepAngleDeg = 8.0f;
		float MaxAngleDeg = 80.0f;
		float EnterHoldSec = 0.35f;
		float TransitionSec = 0.8f;
		float MultStepSec = 2.0f;
		float RateScale = 1.0f;

		bool bDrifting = false;
		float CandidateSec = 0.0f;
		float GapSec = 0.0f;
		float ChainSec = 0.0f;
		int32 Multiplier = 1;
		/** Points of the chain in progress (lost by LoseChain). */
		float ChainScore = 0.0f;
		/** Banked points of finished chains. */
		float ZoneScore = 0.0f;

		void Reset();
		/** Advance by Dt seconds. SlipDeg is the body slip angle (sign ignored). */
		void Step(float Dt, float SpeedKmh, float SlipDeg, bool bGrounded);
		/** Crash: the live chain is lost, banked chains stay. */
		void LoseChain();
		/** Leaving the zone / chain timeout: live chain goes into the zone score. */
		void BankChain();
		float GetTotal() const { return ZoneScore + ChainScore; }
	};

	// ---- default placement ------------------------------------------------------------------------------------------
	struct FPlacementOptions
	{
		int32 NumSpeedTraps = 12;
		int32 NumSpeedZones = 5;
		int32 NumDriftZones = 4;
		int32 NumJumps = 5;
		int32 NumRaces = 6;
		int32 NumTimeTrials = 1;
		int32 NumPhotoSpots = 4;
		int32 NumCollectibles = 4;
		int32 Seed = 1337;
		/** Class factor of the reference car (Docs/Tech/FH5_activities.md 4.6): S 1.00, A 1.08, B 1.18, C 1.30, D 1.45. */
		float ClassFactor = 1.18f;
	};

	/**
	 * Places activities on a road network by class / curvature rules (no hand placement): speed traps at the end of straights,
	 * zones on single roads, drift zones on the most winding stretches, jumps only on straight crests (skipped when none exists),
	 * checkpoint races on single roads, one time trial on the LOOP chain (roads whose id starts with "LOOP", else the longest
	 * connected chain) and photo spots / collectibles. Deterministic for a given seed. Region ids come from WorldDef when given.
	 */
	SONNET55FORZA_API void GenerateDefaultActivityDefs(const URoamRoadNetwork& Network, const URoamWorldDefinition* WorldDef, const FPlacementOptions& Options, TArray<FRoamActivityDef>& OutDefs);
}
