// Copyright Epic Games, Inc. All Rights Reserved.

#pragma once

#include "CoreMinimal.h"
#include "Activities/RoamActivityLogic.h"
#include "Core/RoamTypes.h"
#include "Data/RoamWorldDefinition.h"
#include "Subsystems/WorldSubsystem.h"
#include "RoamActivitySubsystem.generated.h"

class ARoamActivityActor;
class ARoamVehicle;
class URoamRoadNetwork;

/** State machine of one activity (Docs/Tech/FH5_activities.md 2.5): Idle -> Armed -> Active -> Evaluating -> Result -> Cooldown. */
UENUM(BlueprintType)
enum class ERoamActivityState : uint8
{
	Idle = 0,
	Armed,
	Active,
	Evaluating,
	Result,
	Cooldown
};

/** What an activity reports when it finishes. Also what the HUD turns into a result card. */
USTRUCT(BlueprintType)
struct SONNET55FORZA_API FRoamActivityResult
{
	GENERATED_BODY()

	UPROPERTY(BlueprintReadOnly, Category = "Activity")
	FName ActivityId;
	UPROPERTY(BlueprintReadOnly, Category = "Activity")
	ERoamActivityType Type = ERoamActivityType::SpeedTrap;
	/** km/h, points, metres or seconds depending on Type. */
	UPROPERTY(BlueprintReadOnly, Category = "Activity")
	float Value = 0.0f;
	UPROPERTY(BlueprintReadOnly, Category = "Activity")
	int32 Stars = 0;
	UPROPERTY(BlueprintReadOnly, Category = "Activity")
	bool bNewBest = false;
	/** Value minus the previous best (0 for the first result). */
	UPROPERTY(BlueprintReadOnly, Category = "Activity")
	float DeltaToBest = 0.0f;
	UPROPERTY(BlueprintReadOnly, Category = "Activity")
	int32 XpAwarded = 0;
	/** False for cancelled / failed attempts (no stars, no best). */
	UPROPERTY(BlueprintReadOnly, Category = "Activity")
	bool bCompleted = true;
	UPROPERTY(BlueprintReadOnly, Category = "Activity")
	FText FailReason;
};

/**
 * One sampled state of the tracked vehicle: the only input of the activity logic (triggers depend on position and velocity, never on
 * overlap volumes). Tests feed these directly through URoamActivitySubsystem::ProcessSample.
 */
struct SONNET55FORZA_API FRoamActivitySample
{
	/** World time in seconds. */
	double Time = 0.0;
	FVector Position = FVector::ZeroVector;
	/** World velocity in cm/s. Ignored (derived from the previous sample) when bHasVelocity is false. */
	FVector VelocityCmS = FVector::ZeroVector;
	bool bHasVelocity = true;
	FVector Forward = FVector::ForwardVector;
	FVector Up = FVector::UpVector;
	int32 WheelsOnGround = 4;

	float GetSpeedKmh() const { return Roam::CmsToKmh(static_cast<float>(VelocityCmS.Size())); }
};

/** Live data of the running attempt for the HUD meter (top-centre while Active). */
struct SONNET55FORZA_API FRoamActivityLiveInfo
{
	FName ActivityId;
	ERoamActivityType Type = ERoamActivityType::SpeedTrap;
	ERoamActivityState State = ERoamActivityState::Idle;
	/** Seconds since the attempt started. */
	float ElapsedSec = 0.0f;
	/** km/h average (zones), points (drift), metres (jump flight), seconds (races: elapsed). */
	float Value = 0.0f;
	int32 StarsNow = 0;
	int32 Checkpoint = 0;
	int32 NumCheckpoints = 0;
	/** Drift only: points of the chain in progress and its multiplier. */
	float ChainScore = 0.0f;
	int32 Multiplier = 1;
};

DECLARE_MULTICAST_DELEGATE_OneParam(FRoamOnActivityResult, const FRoamActivityResult& /*Result*/);
DECLARE_MULTICAST_DELEGATE_TwoParams(FRoamOnActivityStateChanged, FName /*ActivityId*/, ERoamActivityState /*NewState*/);
/** An activity became active/inactive on a route: traffic keeps out of Bounds (expanded by the listener). */
DECLARE_MULTICAST_DELEGATE_ThreeParams(FRoamOnActivityActive, FName /*ActivityId*/, bool /*bActive*/, const FBox& /*Bounds*/);

/**
 * Owner of ALL activity logic (speed traps, speed zones, drift zones, danger signs, checkpoint races, time trials, collectibles,
 * photo spots) - Docs/ARCHITECTURE.md section 3 and Docs/Tech/FH5_activities.md. Data-driven from URoamWorldDefinition::Activities
 * and from URoamActivitySubsystem::GenerateDefaultActivities (runtime placement on the road network); gates are tested with
 * segment-vs-plane crossings in this subsystem's tick (no overlap volumes, no per-actor tick), with sub-frame interpolation of the
 * crossing time and speed. The placed ARoamActivityMarkerActor props are visuals only.
 *
 * CONTRACT used by other systems:
 *   - Results: OnActivityResult carries everything for the HUD card (stars, value, new best); results are also stored via
 *     URoamSaveSubsystem (personal bests, stars, XP) and pushed to the HUD with URoamUISubsystem::PushNotification.
 *   - Cancel conditions: ARoamVehicle::TeleportVehicle / ResetToRoad call NotifyVehicleTeleported, the garage calls NotifyCarChanged
 *     (the subsystem also listens to the tracked vehicle's OnRecovered / OnCarApplied / OnImpact and treats position jumps of more
 *     than 150 m between two samples as a teleport).
 *   - Traffic: OnActivityActive tells URoamTrafficSubsystem where not to spawn.
 *   - HUD: GetLiveInfo() for the live meter, OnActivityStateChanged for the arming/active state.
 */
UCLASS()
class SONNET55FORZA_API URoamActivitySubsystem : public UTickableWorldSubsystem
{
	GENERATED_BODY()

public:
	static URoamActivitySubsystem* Get(const UObject* WorldContext);

	//~ Begin USubsystem / UWorldSubsystem
	virtual void Initialize(FSubsystemCollectionBase& Collection) override;
	virtual void Deinitialize() override;
	virtual bool DoesSupportWorldType(const EWorldType::Type WorldType) const override;
	virtual void OnWorldBeginPlay(UWorld& InWorld) override;
	//~ End

	//~ Begin FTickableGameObject
	virtual void Tick(float DeltaTime) override;
	virtual TStatId GetStatId() const override { RETURN_QUICK_DECLARE_CYCLE_STAT(URoamActivitySubsystem, STATGROUP_Tickables); }
	//~ End

	// ---- registry --------------------------------------------------------------------------------------------------
	const TArray<FRoamActivityDef>& GetActivities() const { return Activities; }
	const FRoamActivityDef* FindActivity(FName ActivityId) const;
	/** Adds (or replaces) a definition at runtime (tests, generated content). */
	void RegisterActivity(const FRoamActivityDef& Definition);
	/** Reloads the list from URoamWorldDefinition. */
	void ReloadFromWorldDefinition();

	/**
	 * Places the default activity set on a road network (~12 speed traps, 5 zones, 4 drift zones, jumps on straight crests only,
	 * 6 checkpoint races, 1 time trial on the LOOP chain, photo spots and collectibles) and registers + spawns them. Returns the
	 * number of activities added. Called automatically from OnWorldBeginPlay when a road network is configured and no activities exist.
	 */
	int32 GenerateDefaultActivities(URoamRoadNetwork* Network);

	/** Removes every activity and its marker actors (tests, regeneration). */
	void ClearActivities();

	/** Spawns a visible marker actor for every activity that has none yet (skips ids already placed in the level). */
	void SpawnMarkers();

	/** `tp` / `act.tp` target: 1-based index, id or unique substring -> a transform on the road shortly before the activity start. */
	bool ResolveActivityTeleport(const FString& Text, FTransform& OutTransform, FString& OutLabel, FString* OutError = nullptr) const;

	// ---- tracking --------------------------------------------------------------------------------------------------
	/** Overrides the tracked vehicle (default: the player pawn). Used by automated tests with SetAIControlled cars. */
	void SetTrackedVehicle(ARoamVehicle* Vehicle);
	ARoamVehicle* GetTrackedVehicle() const;

	/** Feeds one vehicle sample (called by Tick; tests may call it with synthetic samples). */
	void ProcessSample(const FRoamActivitySample& Sample);

	/** Data for the HUD meter of the running attempt. Returns false when nothing is active. */
	bool GetLiveInfo(FRoamActivityLiveInfo& OutInfo) const;
	const FRoamActivityResult& GetLastResult() const { return LastResult; }

	// ---- state -----------------------------------------------------------------------------------------------------
	/** The activity currently Active (timed/zone/race), or NAME_None. At most one at a time. */
	FName GetActiveActivityId() const { return ActiveActivityId; }
	ERoamActivityState GetActivityState(FName ActivityId) const;

	/** Cancels the active attempt (no result, no stars) and shows a short banner. */
	void CancelActive(const FText& Reason);

	/** Teleports/respawn/reset happened: cancels the active attempt and forgets the previous position (no tunnelling artefacts). */
	void NotifyVehicleTeleported(ARoamVehicle* Vehicle);
	/** The player switched cars: cancels the active attempt. */
	void NotifyCarChanged(ARoamVehicle* Vehicle);

	// ---- progress --------------------------------------------------------------------------------------------------
	/** Best value / stars from the save profile. */
	bool GetBestValue(FName ActivityId, float& OutValue) const;
	int32 GetStars(FName ActivityId) const;
	int32 GetTotalStars() const;
	int32 GetMaxStars() const;

	// ---- events ----------------------------------------------------------------------------------------------------
	FRoamOnActivityResult OnActivityResult;
	FRoamOnActivityStateChanged OnActivityStateChanged;
	FRoamOnActivityActive OnActivityActive;

	/** Writes the profile asynchronously after a new personal best (tests switch it off to leave the real save slot alone). */
	bool bAutoSaveOnResult = true;

protected:
	/** Reports a finished attempt: stores best/stars/XP, pushes the HUD card, broadcasts OnActivityResult. */
	void ReportResult(const FRoamActivityResult& Result);

private:
	/** Per-activity runtime state (not serialised). */
	struct FActivityRuntime
	{
		ERoamActivityState State = ERoamActivityState::Idle;
		double CooldownUntil = 0.0;
		bool bApproachShown = false;
		bool bDone = false; // collectibles / photo spots

		// attempt
		double StartTime = 0.0;
		int32 Direction = 1;
		int32 NextGate = 1;
		float PathCm = 0.0f;
		float StoppedSec = 0.0f;
		float WrongWaySec = 0.0f;
		float OffRouteSec = 0.0f;
		float LiveValue = 0.0f;
		TArray<float> Splits;
		RoamActivity::FDriftTracker Drift;

		// jump
		int32 JumpPhase = 0; // 0 armed, 1 flight, 2 validation
		float AirSec = 0.0f;
		float FlightSec = 0.0f;
		float ValidateSec = 0.0f;
		FVector TakeoffPos = FVector::ZeroVector;
		float JumpDistanceCm = 0.0f;
	};

	bool MakeSample(ARoamVehicle* Vehicle, FRoamActivitySample& OutSample) const;
	void BindVehicle(ARoamVehicle* Vehicle);
	void UnbindVehicle();
	void HandleVehicleImpact(ARoamVehicle* Vehicle, float ImpactSpeedMs);
	void HandleVehicleRecovered(ARoamVehicle* Vehicle);
	void HandleCarApplied(ARoamVehicle* Vehicle);

	void SetState(FName ActivityId, ERoamActivityState NewState, double CooldownUntil = 0.0);
	void TryStart(const FRoamActivityDef& Def, FActivityRuntime& RT, const FRoamActivitySample& S, double Dt);
	void UpdateActive(const FRoamActivitySample& S, double Dt);
	void UpdateZone(const FRoamActivityDef& Def, FActivityRuntime& RT, const FRoamActivitySample& S, double Dt);
	void UpdateJump(const FRoamActivityDef& Def, FActivityRuntime& RT, const FRoamActivitySample& S, double Dt);
	void UpdateChain(const FRoamActivityDef& Def, FActivityRuntime& RT, const FRoamActivitySample& S, double Dt);
	void BeginAttempt(const FRoamActivityDef& Def, FActivityRuntime& RT, double StartTime, int32 Direction);
	void FinishAttempt(const FRoamActivityDef& Def, float Value);
	void FailAttempt(const FRoamActivityDef& Def, const FString& Title, const FString& Detail);
	void ShowApproach(const FRoamActivityDef& Def);
	void Notify(ERoamNotifyKind Kind, const FString& Title, const FString& Body, const FLinearColor& Color, float Seconds);
	FString FormatValue(const FRoamActivityDef& Def, float Value) const;
	static float DistanceToRoute(const FRoamActivityDef& Def, const FVector& Position);

	UPROPERTY(Transient)
	TArray<FRoamActivityDef> Activities;

	UPROPERTY(Transient)
	TMap<FName, TObjectPtr<ARoamActivityActor>> Markers;

	UPROPERTY(Transient)
	TWeakObjectPtr<ARoamVehicle> TrackedOverride;

	UPROPERTY(Transient)
	TWeakObjectPtr<ARoamVehicle> BoundVehicle;

	FName ActiveActivityId;
	TMap<FName, FActivityRuntime> Runtime;

	FRoamActivitySample Prev;
	bool bHavePrev = false;
	FRoamActivityResult LastResult;
	bool bBegunPlay = false;

	FDelegateHandle ImpactHandle;
	FDelegateHandle RecoveredHandle;
	FDelegateHandle CarAppliedHandle;
};
