// Copyright Epic Games, Inc. All Rights Reserved.

#pragma once

#include "CoreMinimal.h"
#include "Core/RoamTypes.h"
#include "Math/RandomStream.h"
#include "Traffic/RoamLaneGraph.h"
#include "Traffic/RoamTrafficVehicle.h"

/**
 * Pure (non-UObject) core of the traffic system: the agent array, IDM car following, curvature speed limits, junction tokens and spawn
 * ring management on top of a FRoamLaneGraph. URoamTrafficSubsystem wraps it (player, actors, pooling, events); the automation tests
 * drive it directly. All lengths in cm, speeds in cm/s unless a name says Ms (m/s).
 */
namespace RoamTraffic
{
	// ring distances (Docs/Tech/FH5_traffic_hud_photo.md 2.2)
	constexpr float PhysicsRingCm = 12000.0f;   // full collision body, physics only after a hit
	constexpr float VisibleRingCm = 45000.0f;   // actor with mesh, kinematic movement
	constexpr float DataRingCm = 90000.0f;      // agent struct only; despawn beyond
	constexpr float SpawnMinCm = 50000.0f;
	constexpr float SpawnMaxCm = 75000.0f;
	constexpr int32 MaxVisibleAgents = 40;
	constexpr int32 MaxAgents = 160;
	constexpr float NightDensityFactor = 0.35f;
	constexpr float HitSpeedThresholdCms = 222.0f; // 8 km/h relative speed
	constexpr float PhysicsReactionSeconds = 6.0f;

	/** Intelligent Driver Model acceleration in m/s2. GapM = bumper gap, ClosingMs = own speed minus leader speed. */
	SONNET55FORZA_API float IdmAcceleration(float VMs, float V0Ms, float GapM, float ClosingMs, float AMaxMs2, float BComfortMs2, float HeadwaySec, float MinGapM);

	/** Vehicles per km per direction at density 1 (highway 3.5, regional/village 2.5/2.0, mountain 1.2, dirt 0.4). */
	SONNET55FORZA_API float BaseDensityPerKm(ERoamRoadClass RoadClass);

	/** True if two oriented boxes (XY plane, Dir = forward axis) overlap when grown by MarginCm on every side. */
	SONNET55FORZA_API bool OverlapOrientedBoxes2D(const FVector& CenterA, const FVector& DirA, float HalfLenA, float HalfWidA,
		const FVector& CenterB, const FVector& DirB, float HalfLenB, float HalfWidB, float MarginCm);

	/** The six civilian types (compact, van, lorry, bus, tractor, pickup) with mesh paths under /Game/Forza/Traffic/<id>/. */
	SONNET55FORZA_API void BuildDefaultVehicleTypes(TArray<FRoamTrafficVehicleSpec>& Out);
}

enum class ERoamTrafficAgentState : uint8
{
	Driving = 0,
	Hit,       // physics reaction after a collision with the player
	Obstacle   // settled wreck / stopped car, despawns later
};

struct SONNET55FORZA_API FRoamTrafficAgent
{
	int32 Id = 0;
	int32 TypeIndex = 0;
	int32 Lane = INDEX_NONE;
	int32 NextLane = INDEX_NONE;
	int32 PrevLane = INDEX_NONE;
	float S = 0.0f;      // centre of the vehicle along the lane (cm)
	float V = 0.0f;      // speed (cm/s)
	float Accel = 0.0f;  // m/s2
	float LengthCm = 430.0f;
	float WidthCm = 180.0f;
	float DesiredFactor = 1.0f;
	float MaxSpeedMs = 30.0f;
	float AMax = 2.0f;
	float BComfort = 3.0f;
	float Headway = 1.5f;
	float MinGapM = 3.0f;

	FVector Pos = FVector::ZeroVector;
	FVector Dir = FVector::ForwardVector;
	float YawRateRad = 0.0f;
	float PrevYawRad = 0.0f;

	ERoamTrafficAgentState State = ERoamTrafficAgentState::Driving;
	float StateTime = 0.0f;
	float Age = 0.0f;

	int32 HoldJunction = INDEX_NONE;
	int32 HoldApproachLane = INDEX_NONE;
	float HoldTime = 0.0f;
	float WaitTime = 0.0f;
	float StopTimer = 0.0f;
	float HornCooldown = 0.0f;
	float NearMissCooldown = 0.0f;
	float BlockedByPlayerTime = 0.0f;

	bool bBraking = false;
	bool bBlocksLane = true;
	bool bWantsHorn = false;
};

struct SONNET55FORZA_API FRoamTrafficPlayer
{
	bool bValid = false;
	FVector Location = FVector::ZeroVector;
	FVector Velocity = FVector::ZeroVector;     // cm/s
	FVector PrevVelocity = FVector::ZeroVector; // cm/s one step earlier (impact speed reference)
	FVector Forward = FVector::ForwardVector;
	float HalfLengthCm = 230.0f;
	float HalfWidthCm = 100.0f;
	float MassKg = 1400.0f;
};

struct SONNET55FORZA_API FRoamTrafficContact
{
	int32 AgentIndex = INDEX_NONE;
	bool bCollision = false;
	float GapCm = 0.0f;
	float ClosingKmh = 0.0f;
	float ImpactSpeedMs = 0.0f;
	FVector AgentVelocityAfterCms = FVector::ZeroVector;
	float YawKickDegS = 0.0f;
};

class SONNET55FORZA_API FRoamTrafficSim
{
public:
	void Init(const URoamRoadNetwork& Network, const TArray<FRoamTrafficVehicleSpec>& InTypes, int32 Seed = 4711);
	void SetTypes(const TArray<FRoamTrafficVehicleSpec>& InTypes) { Types = InTypes; }
	/** Removes all agents (ids go to RemovedIds), keeps the graph. */
	void Clear();
	bool IsReady() const { return !Graph.IsEmpty(); }

	const FRoamLaneGraph& GetGraph() const { return Graph; }

	TArray<FRoamTrafficAgent> Agents;
	/** Ids of agents removed since the last DrainRemoved (the subsystem frees their actors). */
	TArray<int32> RemovedIds;
	int32 NumSpawnedTotal = 0;
	int32 NumRemovedTotal = 0;

	/** Creates an agent. SpeedFraction scales min(limit, type max). Returns the agent id or INDEX_NONE. */
	int32 SpawnAgent(int32 LaneId, float S, int32 TypeIndex, float SpeedFraction);
	int32 FindAgentIndex(int32 Id) const;
	void RemoveAgentAt(int32 Index);
	int32 RemoveFarAgents(const FVector& Center, float MaxDistanceCm);

	/**
	 * Keeps the density of the annulus [VisibleRing, DataRing] around Center at the road-class targets by spawning in the ring
	 * [SpawnMin, SpawnMax]. bInitialFill populates 200 m .. DataRing instead (first call, teleports). Returns the number spawned.
	 */
	int32 SpawnAround(const FVector& Center, float Density01, float TimeOfDayFactor, bool bInitialFill, int32 MaxNew, TFunctionRef<bool(const FVector&)> IsSuppressed);

	void Step(float Dt, const FRoamTrafficPlayer& Player, float SpeedScale);

	/** Pose of the vehicle centre on the ground (junction connectors are Bezier blends between the lanes). */
	void ComputePose(const FRoamTrafficAgent& A, FVector& OutPos, FVector& OutDir) const;

	/** Hits and near misses with the player vehicle for agents within ~30 m. */
	void CollectPlayerContacts(const FRoamTrafficPlayer& Player, TArray<FRoamTrafficContact>& Out) const;

	/** Builds the impact data for a collision of AgentIndex with the player (false below the 8 km/h relative-speed threshold). */
	bool MakeCollisionContact(int32 AgentIndex, const FRoamTrafficPlayer& Player, FRoamTrafficContact& Out) const;

	/** Driving -> Hit: stops the lane simulation of the agent and frees its junction token. */
	void ApplyHit(int32 AgentIndex);
	/** Hit -> Obstacle. bBlocksLane tells followers whether the wreck still stands in their lane. */
	void SettleAgent(int32 AgentIndex, bool bBlocksLane);

	int32 GetNumClaims() const { return Claims.Num(); }
	/** Number of agent pairs that hold incompatible claims on one junction right now (must stay 0; used by tests). */
	int32 CountConflictingClaims() const;

	FRandomStream Rand;

private:
	struct FClaim
	{
		int32 Junction = INDEX_NONE;
		int32 AgentId = 0;
		int32 ArmKey = 0;
		int32 Priority = 0;
		float Wait = 0.0f;
		float Eta = 0.0f;
		FVector Arrive = FVector::ForwardVector;
		FVector Exit = FVector::ForwardVector;
		double AcquireTime = 0.0;
	};

	static bool Compatible(const FClaim& A, const FClaim& B);
	bool TryAcquire(FRoamTrafficAgent& A, float GapLineCm, const FRoamLane& L, const FRoamTrafficPlayer& Player);
	FClaim MakeClaim(const FRoamTrafficAgent& A, const FRoamLane& L) const;
	void ReleaseClaim(FRoamTrafficAgent& A);
	void ChooseNextLane(FRoamTrafficAgent& A);
	void StepDriving(int32 Index, float Dt, const FRoamTrafficPlayer& Player, float SpeedScale);
	int32 PickType(ERoamRoadClass RoadClass);

	FRoamLaneGraph Graph;
	TArray<FRoamTrafficVehicleSpec> Types;
	int32 NextAgentId = 1;
	double Time = 0.0;

	TArray<int32> Order;
	TArray<int32> OrderPos;
	TMap<int32, int32> LaneFirst;
	TArray<FClaim> Claims;
	TArray<FClaim> Waiters;
	TArray<FClaim> PrevWaiters;

	struct FSpawnCandidate
	{
		int32 Lane = 0;
		int32 Point = 0;
		float CumWeight = 0.0f;
	};
	TArray<FSpawnCandidate> Candidates;
};
