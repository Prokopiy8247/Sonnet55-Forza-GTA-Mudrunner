// Copyright Epic Games, Inc. All Rights Reserved.

#pragma once

#include "CoreMinimal.h"
#include "Core/RoamTypes.h"
#include "Subsystems/WorldSubsystem.h"
#include "Traffic/RoamTrafficSim.h"
#include "Traffic/RoamTrafficVehicle.h"
#include "RoamTrafficSubsystem.generated.h"

class ARoamVehicle;
class URoamRoadNetwork;

/** Snapshot counters for the debug menu and tests. */
USTRUCT(BlueprintType)
struct SONNET55FORZA_API FRoamTrafficStats
{
	GENERATED_BODY()

	UPROPERTY(BlueprintReadOnly, Category = "Traffic")
	int32 NumAgents = 0;
	UPROPERTY(BlueprintReadOnly, Category = "Traffic")
	int32 NumPhysicsActors = 0;
	UPROPERTY(BlueprintReadOnly, Category = "Traffic")
	int32 NumKinematicActors = 0;
	UPROPERTY(BlueprintReadOnly, Category = "Traffic")
	int32 NumPooledActors = 0;
	UPROPERTY(BlueprintReadOnly, Category = "Traffic")
	int32 NumSpawnedTotal = 0;
	UPROPERTY(BlueprintReadOnly, Category = "Traffic")
	int32 NumDespawnedTotal = 0;
	UPROPERTY(BlueprintReadOnly, Category = "Traffic")
	float Density = 0.0f;
};

DECLARE_MULTICAST_DELEGATE_ThreeParams(FRoamOnTrafficNearMiss, ARoamTrafficVehicle* /*Vehicle*/, float /*GapCm*/, float /*ClosingSpeedKmh*/);
DECLARE_MULTICAST_DELEGATE_ThreeParams(FRoamOnTrafficCollision, ARoamTrafficVehicle* /*Vehicle*/, AActor* /*Other*/, float /*ImpactSpeedMs*/);

/**
 * Civilian traffic of the world (Docs/ARCHITECTURE.md section 3, prompt section 9, design in Docs/Tech/FH5_traffic_hud_photo.md
 * section 2): a lane graph built from the URoamRoadNetwork (FRoamLaneGraph), a pure simulation core (FRoamTrafficSim: compact agent
 * array, IDM car following, curvature and junction speed limits, junction tokens, density-driven spawn ring) and, here, the world
 * glue: player tracking, LOD rings, a pool of ARoamTrafficVehicle actors for the agents within 450 m and the reaction to hits.
 *
 *   data-only    450 - 900 m   agent struct only (spawn ring 500 - 750 m, despawn beyond 900 m)
 *   kinematic    120 - 450 m   pooled actor driven along the lane, no collision (max 40 live actors)
 *   physics body   0 - 120 m   same actor with collision; simulates physics ONLY after the player hit it (relative speed > 8 km/h)
 *
 * CONTRACT used by other systems:
 *   - Density / enabled switch: SetDensity (console `traffic`), SetEnabled.
 *   - Area suppression: activities call SuppressArea so no traffic spawns on their route (unfair crashes are the top complaint).
 *   - Events: OnNearMiss (skill chain), OnCollision (activities fail conditions).
 *   - Reads: URoamRoadNetwork (roads, lanes, speed limits), URoamTimeWeatherSubsystem (density at night, rain speed, headlights),
 *     the player pawn position/velocity.
 *   - Without a DA_RoadNetwork the system stays idle, except on maps whose name contains "Test" (L_Test) where it builds the
 *     synthetic test network so `traffic 1` has something to drive on.
 */
UCLASS()
class SONNET55FORZA_API URoamTrafficSubsystem : public UTickableWorldSubsystem
{
	GENERATED_BODY()

public:
	static URoamTrafficSubsystem* Get(const UObject* WorldContext);

	//~ Begin USubsystem / UWorldSubsystem
	virtual void Initialize(FSubsystemCollectionBase& Collection) override;
	virtual void Deinitialize() override;
	virtual bool DoesSupportWorldType(const EWorldType::Type WorldType) const override;
	//~ End

	//~ Begin FTickableGameObject
	virtual void Tick(float DeltaTime) override;
	virtual TStatId GetStatId() const override { RETURN_QUICK_DECLARE_CYCLE_STAT(URoamTrafficSubsystem, STATGROUP_Tickables); }
	//~ End

	// ---- control ---------------------------------------------------------------------------------------------------
	/** 0..1 multiplier of all per-road-class densities (console `traffic <0..1>`). 0 stops spawning; existing agents leave out of view. */
	UFUNCTION(BlueprintCallable, Category = "Roam|Traffic")
	void SetDensity(float Density01);
	UFUNCTION(BlueprintCallable, Category = "Roam|Traffic")
	float GetDensity() const { return Density; }

	UFUNCTION(BlueprintCallable, Category = "Roam|Traffic")
	void SetEnabled(bool bNewEnabled);
	UFUNCTION(BlueprintCallable, Category = "Roam|Traffic")
	bool IsEnabled() const { return bEnabled; }

	/** Removes every agent immediately (teleports, car switches, tests). */
	UFUNCTION(BlueprintCallable, Category = "Roam|Traffic")
	void ClearAll();
	/** Debug (console `traffic showcase`): parks one vehicle of every type in a row ahead of the player, static, outside the simulation. Removed by ClearAll. */
	void SpawnShowcase();
	/** Debug (console `traffic check`): for every agent compares the side of the road and the ground contact with the real road network and level geometry. */
	FString RunSelfCheck();
	/** Debug (console `traffic ram [metres] [type]`): parks a stopped car in the player's lane that far ahead, to test the crash reaction. */
	FString SpawnBlocker(float AheadMetres, int32 TypeIndex);

	/**
	 * Keeps traffic out of a sphere for Seconds (activity routes use a corridor of spheres). Returns a handle for
	 * ReleaseSuppression. Overlapping suppressions combine.
	 */
	int32 SuppressArea(const FVector& Center, float RadiusCm, float Seconds);
	void ReleaseSuppression(int32 Handle);
	/** True if any active suppression covers the point. */
	bool IsSuppressed(const FVector& Location) const;

	// ---- road data ---------------------------------------------------------------------------------------------------
	/** Uses this network instead of the game instance's (tests, smoke runs). nullptr restores the default. Rebuilds the lane graph. */
	void SetRoadNetworkOverride(URoamRoadNetwork* Network);
	/** Builds the synthetic 3x3 km test grid and uses it (console `traffic synth`). */
	void UseSyntheticNetwork();
	bool IsSimReady() const { return Sim.IsValid() && Sim->IsReady(); }
	const FRoamTrafficSim* GetSim() const { return Sim.Get(); }

	// ---- vehicle types ---------------------------------------------------------------------------------------------
	void RegisterVehicleType(const FRoamTrafficVehicleSpec& Spec);
	const TArray<FRoamTrafficVehicleSpec>& GetVehicleTypes() const { return VehicleTypes; }

	// ---- queries / stats -------------------------------------------------------------------------------------------
	FRoamTrafficStats GetStats() const;
	/** World positions of all live agents (minimap dots, debug draw). */
	void GetAgentLocations(TArray<FVector>& OutLocations) const;
	void SetDebugDraw(bool bNewDebugDraw) { bDebugDraw = bNewDebugDraw; }
	bool IsDebugDraw() const { return bDebugDraw; }

	// ---- events ----------------------------------------------------------------------------------------------------
	FRoamOnTrafficNearMiss OnNearMiss;
	FRoamOnTrafficCollision OnCollision;

private:
	struct FSuppression
	{
		int32 Handle = 0;
		FVector Center = FVector::ZeroVector;
		float RadiusCm = 0.0f;
		double ExpireWorldTime = 0.0; // <= 0: until released
	};

	void ExpireSuppressions();

	bool EnsureSim(float DeltaTime);
	void BuildSim(URoamRoadNetwork* Network);
	void ResolveMissingMeshes();
	/** Replaces the built-in type list with DA_TrafficVehicles (real wheel layouts, paint variants) when the asset exists. */
	void LoadCatalogTypes();
	bool GatherPlayer(float DeltaTime);
	void DrainRemoved();
	void RemoveOutOfView();
	void HandleContacts();
	void SyncActors(float DeltaTime);
	void DrawDebug() const;

	ARoamTrafficVehicle* AcquireActor();
	ARoamTrafficVehicle* FindOrAcquireActor(int32 AgentIndex);
	void ReleaseActor(int32 AgentId);
	void OnVehicleBodyHit(ARoamTrafficVehicle* Vehicle, AActor* Other, const FVector& NormalImpulse);

	float Density = 0.6f;
	bool bEnabled = true;
	bool bDebugDraw = false;
	int32 NextSuppressionHandle = 1;
	TArray<FSuppression> Suppressions;
	TArray<FRoamTrafficVehicleSpec> VehicleTypes;
	FRoamTrafficStats Stats;

	TUniquePtr<FRoamTrafficSim> Sim;
	UPROPERTY(Transient)
	TObjectPtr<URoamRoadNetwork> SyntheticNetwork;
	UPROPERTY(Transient)
	TObjectPtr<URoamRoadNetwork> NetworkOverride;
	UPROPERTY(Transient)
	TArray<TObjectPtr<ARoamTrafficVehicle>> PoolActors;

	TArray<ARoamTrafficVehicle*> FreePool;
	TArray<TObjectPtr<ARoamTrafficVehicle>> ShowcaseActors;
	TMap<int32, ARoamTrafficVehicle*> ActorOfAgent;
	TArray<int32> BodyHitAgents; // agent ids reported by the physics hit callback, resolved in HandleContacts

	FRoamTrafficPlayer Player;
	TWeakObjectPtr<AActor> PlayerActor;
	FVector LastPlayerLocation = FVector::ZeroVector;
	bool bHasLastPlayerLocation = false;
	FVector ViewLocation = FVector::ZeroVector;
	FVector ViewForward = FVector::ForwardVector;
	bool bNight = false;
	float SpeedScale = 1.0f;
	float DayFactor = 1.0f;

	float SpawnTimer = 0.0f;
	float NetworkRetryTimer = 0.0f;
	bool bNeedInitialFill = true;
	bool bLoggedNoNetwork = false;
};
