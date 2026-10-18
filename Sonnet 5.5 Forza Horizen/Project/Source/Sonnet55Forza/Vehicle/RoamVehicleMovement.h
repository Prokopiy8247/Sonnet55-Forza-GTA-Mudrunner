// Copyright Epic Games, Inc. All Rights Reserved.

#pragma once

#include "CoreMinimal.h"
#include "Components/ActorComponent.h"
#include "Core/RoamTypes.h"
#include "CollisionQueryParams.h"
#include "Vehicle/RoamDrivetrain.h"
#include "Vehicle/RoamTireModel.h"
#include "RoamVehicleMovement.generated.h"

class ARoamVehicle;
class UPrimitiveComponent;
class URoamCarDefinition;

/**
 * Which model drives the body. KinematicPlaceholder is the skeleton's stand-in so the car can be driven for UI/camera work.
 * Physics is the project-owned raycast/spring model on a Chaos rigid body (Docs/ARCHITECTURE.md section 4).
 */
UENUM(BlueprintType)
enum class ERoamVehicleSimMode : uint8
{
	KinematicPlaceholder = 0,
	Physics
};

/** Statistics of the fixed-step physics callback, used to verify the stepping decision documented in Docs/Tech/BUILD_AND_RUN.md. */
USTRUCT(BlueprintType)
struct SONNET55FORZA_API FRoamPhysicsStepStats
{
	GENERATED_BODY()

	UPROPERTY(BlueprintReadOnly, Category = "Physics")
	int64 NumSteps = 0;
	UPROPERTY(BlueprintReadOnly, Category = "Physics")
	double TotalDt = 0.0;
	UPROPERTY(BlueprintReadOnly, Category = "Physics")
	float MinDt = 1.0e9f;
	UPROPERTY(BlueprintReadOnly, Category = "Physics")
	float MaxDt = 0.0f;
	UPROPERTY(BlueprintReadOnly, Category = "Physics")
	double LastSimTime = 0.0;

	float GetAverageDt() const { return NumSteps > 0 ? static_cast<float>(TotalDt / static_cast<double>(NumSteps)) : 0.0f; }
	float GetAverageHz() const { return TotalDt > 0.0 ? static_cast<float>(static_cast<double>(NumSteps) / TotalDt) : 0.0f; }
};

/** Static data of one wheel/suspension corner, built from the car definition + tuning (SI units except where noted). */
struct FRoamWheelCfg
{
	FVector MountLocalCm = FVector::ZeroVector;   // top of the suspension travel in car space (cm)
	FVector HubRestLocalCm = FVector::ZeroVector; // wheel centre at rest in car space (cm)
	float RadiusM = 0.33f;
	float TravelUpM = 0.09f;
	float TravelDownM = 0.09f;
	float RestExtM = 0.09f;                       // rest distance mount -> hub
	float Spring = 30000.0f;                      // N/m
	float BumpDamp = 2500.0f;                     // N s/m
	float ReboundDamp = 3500.0f;
	float StopK = 200000.0f;
	float ArbK = 15000.0f;                        // anti-roll N/m of differential travel
	float StaticLoadN = 3000.0f;
	float InertiaKgM2 = 1.3f;                     // wheel + tyre + brake
	float StaticCamberDeg = -1.0f;
	float CamberGainDegPerM = -8.0f;
	bool bFront = true;
	bool bLeft = true;
};

/** Dynamic state of one wheel (written by the physics step, read by the game-thread telemetry). */
struct FRoamWheelState
{
	float Omega = 0.0f;           // rad/s, positive = forward
	float ExtM = 0.09f;           // current distance mount -> hub
	float CompressionM = 0.0f;    // rest - ext (positive = compressed)
	float Fz = 0.0f;              // N
	float Fx = 0.0f;
	float Fy = 0.0f;
	float SlipRatio = 0.0f;
	float SlipAngleRad = 0.0f;
	float SlideNorm = 0.0f;
	float SteerRad = 0.0f;
	float AbsRelease = 1.0f;
	float BrakeTorque = 0.0f;
	bool bGrounded = false;
	ERoamSurface Surface = ERoamSurface::Asphalt;
};

/**
 * Vehicle movement/simulation component of ARoamVehicle. This is the contract between the player's input, the physics model,
 * telemetry consumers (UI, audio, FX, activities) and the camera.
 *
 * ---- OWNER: vehicle-physics agent ------------------------------------------------------------------------------------------
 * The skeleton ships a kinematic bicycle-model PLACEHOLDER (TickPlaceholder) that follows the ground with line traces so the
 * car can be driven in the test map. The physics owner replaces it by the real model:
 *   - set SimMode = Physics (body gets bSimulatePhysics, mass/COM/inertia from the car definition),
 *   - implement StepPhysics(), which is called ONCE PER PHYSICS SOLVER STEP with a fixed small dt (see below),
 *   - fill Telemetry every frame (TickComponent still runs once per frame for the game-thread side),
 *   - keep every public function below, they are used by other systems.
 *
 * PHYSICS STEPPING (decision, verified in the 5.8.2 engine source - details in Docs/Tech/BUILD_AND_RUN.md):
 *   FBodyInstance::AddCustomPhysics is NOT a per-substep hook with Chaos (it runs once per frame with the frame delta), so it is
 *   not used. Instead this component registers for UActorComponent::AsyncPhysicsTickComponent, which Chaos calls before EVERY
 *   solver step (fixed dt = UPhysicsSettings::AsyncFixedTimeStepSize = 1/120 s with bTickPhysicsAsync). The callback runs on the
 *   game thread with the physics thread parked ("frozen game thread"), so it may read and write both game- and physics-thread
 *   state; per-body physics-thread access is FBodyInstance::GetBodyInstanceAsyncPhysicsTickHandle().
 */
UCLASS(ClassGroup = (Roam), meta = (BlueprintSpawnableComponent))
class SONNET55FORZA_API URoamVehicleMovement : public UActorComponent
{
	GENERATED_BODY()

public:
	URoamVehicleMovement();

	//~ Begin UActorComponent
	virtual void BeginPlay() override;
	virtual void TickComponent(float DeltaTime, ELevelTick TickType, FActorComponentTickFunction* ThisTickFunction) override;
	virtual void AsyncPhysicsTickComponent(float DeltaTime, float SimTime) override;
	//~ End UActorComponent

	// ---- setup (called by ARoamVehicle) ----------------------------------------------------------------------------
	/** Takes the data of a car (mass, engine, gears, tyres ...). Resets the dynamic state. Safe to call on a live vehicle. */
	void InitFromDefinition(URoamCarDefinition* Definition);
	URoamCarDefinition* GetCarDefinition() const { return CarDefinition; }

	/** Selects the model. Physics mode requires a Body with collision; the owner enables it when the model is ready. */
	void SetSimMode(ERoamVehicleSimMode NewMode);
	ERoamVehicleSimMode GetSimMode() const { return SimMode; }

	// ---- driver inputs (raw, set every frame by the controller / AI / tests) ---------------------------------------
	/** 0..1 */
	void SetThrottleInput(float Value) { ThrottleInput = FMath::Clamp(Value, 0.0f, 1.0f); }
	/** 0..1 (reverse is engaged by the gearbox logic when stopped, see Telemetry.bReversing) */
	void SetBrakeInput(float Value) { BrakeInput = FMath::Clamp(Value, 0.0f, 1.0f); }
	/** -1 (left) .. +1 (right) */
	void SetSteerInput(float Value) { SteerInput = FMath::Clamp(Value, -1.0f, 1.0f); }
	/** 0..1 */
	void SetHandbrakeInput(float Value) { HandbrakeInput = FMath::Clamp(Value, 0.0f, 1.0f); }
	void ShiftUp();
	void ShiftDown();
	float GetThrottleInput() const { return ThrottleInput; }
	float GetBrakeInput() const { return BrakeInput; }
	float GetSteerInput() const { return SteerInput; }
	float GetHandbrakeInput() const { return HandbrakeInput; }

	/**
	 * Keyboard users press digital keys: when true, steering/throttle/brake are rate-limited towards the raw input so a key press
	 * behaves like an analogue stick. AI and scripted tests switch it off (raw values are used as given).
	 */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Input")
	bool bFilterInputs = true;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Input")
	float SteerRiseRate = 3.0f;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Input")
	float SteerFallRate = 6.0f;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Input")
	float PedalRiseRate = 6.0f;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Input")
	float PedalFallRate = 10.0f;

	// ---- assists / tuning ------------------------------------------------------------------------------------------
	void SetAssists(const FRoamAssistSettings& NewAssists);
	const FRoamAssistSettings& GetAssists() const { return Assists; }
	void SetAssist(ERoamAssist Assist, bool bEnabled);
	/** Applies the player's tuning (rebuilds gear ratios, spring/damper scales, brake bias ... in the physics model). */
	void SetTuning(const FRoamTuning& NewTuning);
	const FRoamTuning& GetTuning() const { return Tuning; }
	/** Upgrade tiers per slot id; the physics owner turns them into spec modifiers. */
	void SetUpgrades(const TMap<FName, int32>& NewUpgrades);

	// ---- state -----------------------------------------------------------------------------------------------------
	const FRoamVehicleTelemetry& GetTelemetry() const { return Telemetry; }
	float GetSpeedKmh() const { return Telemetry.SpeedKmh; }

	/** Zeroes velocity, wheel speeds, gear and the distance counter (after a teleport / reset / car switch). */
	void ResetState(bool bKeepVelocity = false);
	/** Hint for the ground-follow of the placeholder / for teleports: the movement is told the body has been moved. */
	void NotifyTeleported();
	/** After a teleport that keeps speed: re-applies a forward speed in cm/s (placeholder model; the physics model sets the body velocity). */
	void RestoreForwardSpeed(float ForwardSpeedCmS);

	const FRoamPhysicsStepStats& GetPhysicsStepStats() const { return StepStats; }
	void ResetPhysicsStepStats() { StepStats = FRoamPhysicsStepStats(); }

	/** Placeholder top speed in km/h (the skeleton's bicycle model); ignored by the physics model. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Placeholder")
	float PlaceholderTopSpeedKmh = 190.0f;

	/** True (default): InitFromDefinition switches to the raycast/spring physics model; false keeps the kinematic placeholder. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Physics")
	bool bUsePhysicsModel = true;

	/** True once the Body has a live simulated rigid body with the car's mass properties (the model runs only then). */
	bool IsPhysicsReady() const { return bPhysicsReady; }
	/** Effective mass in kg after upgrades. */
	float GetEffectiveMassKg() const { return MassKg; }
	/** Multi-line description of every wheel (load, slip, surface ...) for the `phys wheels` console command. */
	FString DescribeWheels() const;
	/** Static + dynamic wheel data for tests and debugging. */
	const FRoamWheelState& GetWheelState(int32 Index) const { return Wheels[FMath::Clamp(Index, 0, 3)]; }
	const FRoamWheelCfg& GetWheelCfg(int32 Index) const { return WheelCfg[FMath::Clamp(Index, 0, 3)]; }
	float GetTcsFactor() const { return TcsFactor; }
	int32 GetGear() const { return Drivetrain.Gear; }
	float GetEngineRpm() const { return Drivetrain.EngineRPM; }

protected:
	/** The vehicle that owns this component (cached in BeginPlay). */
	UPROPERTY(Transient)
	TObjectPtr<ARoamVehicle> OwnerVehicle;

	UPROPERTY(Transient)
	TObjectPtr<URoamCarDefinition> CarDefinition;

	/** Called once per physics solver step (fixed dt) while SimMode == Physics: suspension, tyres, drivetrain, brakes, aero, assists. */
	void StepPhysics(float FixedDt, float SimTime);

	UFUNCTION()
	void OnBodyHit(UPrimitiveComponent* HitComponent, AActor* OtherActor, UPrimitiveComponent* OtherComponent, FVector NormalImpulse, const FHitResult& Hit);

private:
	// ---- physics model (RoamVehicleMovement.cpp, "physics model" section) -----------------------------------------------
	void EnsureBodyReady();
	void RebuildPhysicsConfig();
	void TickPhysicsGameThread(float DeltaTime);
	void ResetPhysicsState(bool bKeepVelocity);
	const URoamCarDefinition* GetActiveDefinition() const;

	bool bPhysicsReady = false;
	bool bBodyConfigured = false;
	bool bHitDelegateBound = false;
	float MassKg = 1300.0f;
	FVector ComLocalCm = FVector(0.0, 0.0, 45.0);
	float WheelbaseM = 2.6f;
	float TrackFrontM = 1.55f;
	FRoamWheelCfg WheelCfg[4];
	FRoamWheelState Wheels[4];
	FRoamDrivetrain Drivetrain;
	float TorqueScale = 1.0f;
	RoamTire::FShape TireShape[2];                 // front, rear
	FCollisionQueryParams WheelQueryParams;
	float GripScale = 1.0f;
	float BrakeScale = 1.0f;
	float AeroScale = 1.0f;
	float BrakeBiasFront = 0.6f;
	float RearShare = 0.6f;
	float CachedWetness = 0.0f;
	float SteerAngleDeg = 0.0f;
	float TcsFactor = 1.0f;
	float StmBrakeLeft = 0.0f;
	float StmBrakeRight = 0.0f;
	float StmActiveTimer = 0.0f;
	float WingDeploy01 = 0.0f;
	float AirTimer = 0.0f;
	float StepsSinceTelemetry = 0.0f;
	bool bNaNReported = false;
	FVector PrevStepVelocityCmS = FVector::ZeroVector;
	FVector SmoothedAccelMs2 = FVector::ZeroVector;  // proper acceleration in body axes (m/s^2): x forward, y right, z up
	FVector LastStepVelocityCmS = FVector::ZeroVector;
	FVector LastStepAngularVelocity = FVector::ZeroVector;
	FQuat LastStepRotation = FQuat::Identity;
	FVector LastStepLocationCm = FVector::ZeroVector;
	FVector LastStepComCm = FVector::ZeroVector;
	float LastStepDownforceN = 0.0f;
	float PhysicsDistanceM = 0.0f;
	bool bHaveStepData = false;

	UPROPERTY(Transient)
	TObjectPtr<URoamCarDefinition> FallbackDefinition;

	UPROPERTY(Transient)
	TObjectPtr<UStaticMesh> ProxyCubeMesh;

	void ApplyInputFilter(float DeltaTime);
	void TickPlaceholder(float DeltaTime);
	void UpdatePlaceholderGear(float SpeedKmh);

	ERoamVehicleSimMode SimMode = ERoamVehicleSimMode::KinematicPlaceholder;

	// raw inputs
	float ThrottleInput = 0.0f;
	float BrakeInput = 0.0f;
	float SteerInput = 0.0f;
	float HandbrakeInput = 0.0f;
	// filtered values (what the model sees)
	float Throttle = 0.0f;
	float Brake = 0.0f;
	float Steer = 0.0f;
	float Handbrake = 0.0f;

	FRoamAssistSettings Assists;
	FRoamTuning Tuning;
	TMap<FName, int32> Upgrades;

	FRoamVehicleTelemetry Telemetry;
	FRoamPhysicsStepStats StepStats;

	// placeholder state
	float PlaceholderForwardSpeed = 0.0f; // cm/s
	float PlaceholderVerticalSpeed = 0.0f; // cm/s
	FVector LastLocation = FVector::ZeroVector;
	FVector LastVelocityCmS = FVector::ZeroVector;
	bool bHaveLastLocation = false;
	int32 ManualGearRequest = 0;
	float AirTime = 0.0f;
};
