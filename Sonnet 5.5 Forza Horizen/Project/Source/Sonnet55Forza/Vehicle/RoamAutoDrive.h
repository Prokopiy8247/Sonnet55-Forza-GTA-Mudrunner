// Copyright Epic Games, Inc. All Rights Reserved.

#pragma once

#include "CoreMinimal.h"
#include "Subsystems/WorldSubsystem.h"
#include "Core/RoamTypes.h"
#include "RoamAutoDrive.generated.h"

class ARoamVehicle;
class URoamCarDefinition;
class URoamRoadNetwork;

/** A position on the road graph: road index, distance along it (cm) and the direction of travel (+1 = increasing S). */
struct FRoamPathCursor
{
	int32 RoadIndex = INDEX_NONE;
	float S = 0.0f;
	int32 Dir = 1;
};

/** Everything the autopilot measures while it drives (printed as ROAM_AUTODRIVE_END). */
struct FRoamAutoDriveStats
{
	double GameSeconds = 0.0;
	double DistanceM = 0.0;
	float MaxSpeedKmh = 0.0f;
	float MinZMarginCm = 1.0e9f;
	float MaxZMarginCm = -1.0e9f;
	float MaxLateralErrCm = 0.0f;
	float MaxRollDeg = 0.0f;
	float MaxPitchDeg = 0.0f;
	float MaxYawRateDeg = 0.0f;
	float MaxSlipDeg = 0.0f;
	float MaxLatG = 0.0f;
	float MinVertG = 1.0e9f;
	float MaxVertG = -1.0e9f;
	int32 StuckEvents = 0;
	int32 OffRoadEvents = 0;
	int32 FallEvents = 0;
	int32 LostEvents = 0;
	int32 Laps = 0;
	int32 Bumps = 0;
	int32 Hitches50 = 0;
	int32 Hitches100 = 0;
	int32 Hitches250 = 0;
	float MaxFrameMs = 0.0f;
	TArray<float> FrameMs;
};

/**
 * Road-following AUTOPILOT + integration test driver for the player car (Docs/Tech/DRIVE_TESTS.md appendix "Integration pass").
 *
 *  - `autodrive [on|off|stat] [speedKmh] [stopAfterKm]`: pure-pursuit steering along the URoamRoadNetwork in the lane of the road under
 *    the car; at junctions it follows the scenic LOOP (HWY_EAST > LOOP_COAST > LOOP_SOUTH > LOOP_VALLEY > LOOP_PASS > LOOP_DESC) when the
 *    car is on it, otherwise the most straight arm. Speed target = cruise speed (default: the road's speed limit) lowered by the
 *    curvature of the path ahead (v = sqrt(aLat / kappa), brake-distance aware). Uses SetThrottle/SetBrake/SetSteer, works for any car.
 *  - Measures distance, speed, z-margin over the road, lateral error, stuck / off-road / fall events (recovers by teleporting onto the lane),
 *    frame-time hitches. Log markers ROAM_AUTODRIVE_*.
 *  - `cartest [first] [last] [driveSeconds] [cams]`: drops each garage car on the road, checks its stance at rest (ride height, wheel
 *    positions against the ground, jitter), drives full throttle and brakes, reads lamp materials / wheel animation back. ROAM_CARTEST_*.
 */
UCLASS()
class SONNET55FORZA_API URoamAutoDriveSubsystem : public UTickableWorldSubsystem
{
	GENERATED_BODY()

public:
	static URoamAutoDriveSubsystem* Get(const UObject* WorldContext);

	//~ Begin USubsystem / UWorldSubsystem
	virtual bool DoesSupportWorldType(const EWorldType::Type WorldType) const override;
	virtual void Deinitialize() override;
	//~ End

	//~ Begin FTickableGameObject
	virtual void Tick(float DeltaTime) override;
	virtual TStatId GetStatId() const override { RETURN_QUICK_DECLARE_CYCLE_STAT(URoamAutoDriveSubsystem, STATGROUP_Tickables); }
	//~ End

	/** CruiseKmh <= 0: use the speed limit of the road. StopAfterKm <= 0: run until stopped. */
	bool StartAutoDrive(float CruiseKmh, float StopAfterKm, FString& OutMessage);
	void StopAutoDrive(const TCHAR* Reason);
	bool IsActive() const { return bActive; }
	FString DescribeStatus() const;
	const FRoamAutoDriveStats& GetStats() const { return Stats; }

	/** Multiplies the lateral acceleration the speed planner allows in corners (default 1). */
	void SetGripFactor(float Factor) { GripFactor = FMath::Clamp(Factor, 0.2f, 4.0f); }
	/** Lane to drive in (1 = nearest the centreline); the sign follows the direction of travel. */
	void SetLane(int32 Lane) { LaneNumber = FMath::Max(Lane, 1); }
	void SetFollowLoop(bool bFollow) { bFollowLoop = bFollow; }
	/** Target speed = min(cruise cap, road limit x this factor). Default 1.0 without a cruise speed, 1.3 with one. <= 0: automatic. */
	void SetOverspeed(float Factor) { OverspeedFactor = Factor; }
	/** Teleports the car onto the lane of a road at S (metres, direction of increasing S) so a run can start anywhere. RoadId may omit the "#k". */
	bool PlaceOnRoad(const FString& RoadId, float SMeters, FString& OutMessage);
	/** Quit the game when the autopilot stops / the car test ends (unattended runs). */
	void SetQuitWhenDone(bool bQuit) { bQuitWhenDone = bQuit; }

	bool StartCarTest(int32 First, int32 Last, float DriveSeconds, bool bCameraShots, FString& OutMessage);
	bool IsCarTestRunning() const { return CarTest.Phase != ECarTestPhase::Idle; }

private:
	enum class ECarTestPhase : uint8 { Idle, Spawn, Settle, Drive, Brake, Cams };

	struct FCarTestState
	{
		ECarTestPhase Phase = ECarTestPhase::Idle;
		int32 First = 1;
		int32 Last = 1;
		int32 Current = 1;
		float DriveSeconds = 6.0f;
		bool bCams = false;
		float PhaseTime = 0.0f;
		FTransform Start;
		FName CarId;
		// settle window
		float RestMaxSpeedKmh = 0.0f;
		float RestMinVertG = 1.0e9f;
		float RestMaxVertG = -1.0e9f;
		float RestMaxTiltDeg = 0.0f;
		float RestMinZ = 1.0e9f;
		float RestMaxZ = -1.0e9f;
		bool bRestLogged = false;
		bool bShotTaken = false;
		// drive window
		float DriveMaxSpeedKmh = 0.0f;
		float TimeTo100 = -1.0f;
		float DriveMaxRoll = 0.0f;
		float DriveMaxPitch = 0.0f;
		float DriveMinVertG = 1.0e9f;
		float DriveMaxVertG = -1.0e9f;
		float DriveMaxSlip = 0.0f;
		float DriveMaxYawRate = 0.0f;
		int32 DriveMinWheels = 4;
		float DriveMaxZ = -1.0e9f;
		float DriveStartZ = 0.0f;
		FVector DriveStartLocation = FVector::ZeroVector;
		FVector DriveStartForward = FVector::ForwardVector;
		float SpinDegAtMark = 0.0f;
		float SpinMarkTime = 0.0f;
		bool bSteerMarked = false;
		bool bWheelVisLogged = false;
		float TailBefore = 0.0f;
		// brake window
		float BrakeStartSpeedKmh = 0.0f;
		FVector BrakeStartLocation = FVector::ZeroVector;
		bool bBrakeLampLogged = false;
		int32 CamIndex = 0;
		bool bCamShot = false;
	};

	// ---- road following -----------------------------------------------------------------------------------------------------------
	bool EnsureNetwork();
	void BuildRoadCaches();
	bool PickNext(const FRoamPathCursor& From, FRoamPathCursor& Out) const;
	bool Advance(FRoamPathCursor& Cursor, float DistanceCm) const;
	float CrestLimitBetween(int32 RoadIndex, float S0Cm, float S1Cm) const;
		FVector LanePosition(const FRoamPathCursor& Cursor, FVector* OutTangent = nullptr, float* OutSpeedLimitKmh = nullptr, ERoamSurface* OutSurface = nullptr) const;
	bool AcquireCursor(const ARoamVehicle* Vehicle, FRoamPathCursor& OutCursor, FRoamRoadHit& OutHit) const;
	float PlanSpeedMs(const ARoamVehicle* Vehicle, const FRoamPathCursor& From, float CruiseMs) const;
	void DriveTick(ARoamVehicle* Vehicle, float DeltaTime);
	void Recover(ARoamVehicle* Vehicle, const TCHAR* Why, float AheadCm);
	void ResetStats();
	void LogEnd(const TCHAR* Reason) const;
	void RecordFrame(float RealDt);

	// ---- car test -----------------------------------------------------------------------------------------------------------------
	void TickCarTest(float DeltaTime);
	void CarTestBeginCar();
	void CarTestLogRest(ARoamVehicle* Vehicle);
	void CarTestFinishDrive(ARoamVehicle* Vehicle);
	void CarTestEnd(const TCHAR* Reason);
	void TakeShot(const FString& Tag);

	void RequestQuit();

	bool bActive = false;
	bool bQuitWhenDone = false;
	bool bFollowLoop = true;
	float CruiseKmhSetting = 0.0f;
	float StopAfterKm = 0.0f;
	float GripFactor = 1.0f;
	TWeakObjectPtr<AActor> LeadActor;
	FVector LeadLastPos = FVector::ZeroVector;
	double LeadLastTime = 0.0;
	float LeadSpeedMs = 0.0f;
	float FollowBlockTimer = 0.0f;
	float OverspeedFactor = -1.0f;
	bool bSeenLastLoopRoad = false;
	float CachedLatG = 0.6f;
	int32 LaneNumber = 1;

	UPROPERTY(Transient)
	TObjectPtr<URoamRoadNetwork> Network;

	TArray<int32> RoadLoopIndex;     // per road: position in the loop sequence or INDEX_NONE
	TArray<FName> RoadBaseName;      // per road: id without the "#k" split suffix
	TArray<TArray<float>> RoadCrestLimit;   // per road, per 2 m bucket: highest speed (m/s) that keeps the wheels loaded over the vertical profile there
	bool bCachesBuilt = false;

	FRoamPathCursor Cursor;
	bool bCursorValid = false;
	FRoamAutoDriveStats Stats;
	float PlanTimer = 0.0f;
	float PlannedSpeedMs = 0.0f;
	float SteerCmd = 0.0f;
	float StuckTimer = 0.0f;
	float OffRoadTimer = 0.0f;
	float GraceTimer = 0.0f;
	float StatusTimer = 0.0f;
	float BumpCooldown = 0.0f;
	double LastRealTime = 0.0;
	double StartRealTime = 0.0;
	float LastDistanceKm = 0.0f;
	float LastLateralCm = 0.0f;
	FName LastLoggedRoad;
	FName LastCarId;

	FCarTestState CarTest;
};
