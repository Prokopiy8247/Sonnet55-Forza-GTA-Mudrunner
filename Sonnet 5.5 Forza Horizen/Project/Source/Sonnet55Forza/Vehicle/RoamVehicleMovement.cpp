// Copyright Epic Games, Inc. All Rights Reserved.

#include "Vehicle/RoamVehicleMovement.h"

#include "Console/RoamConsoleSubsystem.h"
#include "Core/RoamCollision.h"
#include "Core/RoamLog.h"
#include "Core/RoamSettings.h"
#include "Data/RoamCarDefinition.h"
#include "Engine/World.h"
#include "GameFramework/Actor.h"
#include "PhysicalMaterials/PhysicalMaterial.h"
#include "Vehicle/RoamVehicle.h"
#include "Vehicle/RoamVehicleBody.h"
#include "World/RoamTimeWeatherSubsystem.h"

URoamVehicleMovement::URoamVehicleMovement()
{
	PrimaryComponentTick.bCanEverTick = true;
	PrimaryComponentTick.bStartWithTickEnabled = true;
	// Pre-physics: inputs are consumed before the solver step of this frame.
	PrimaryComponentTick.TickGroup = TG_PrePhysics;
	bAutoActivate = true;
}

void URoamVehicleMovement::BeginPlay()
{
	Super::BeginPlay();
	OwnerVehicle = Cast<ARoamVehicle>(GetOwner());

	// Register for the fixed-step physics callback. It runs once per Chaos solver step (see the class comment and
	// Docs/Tech/BUILD_AND_RUN.md "Physics stepping"). In the skeleton it only gathers step statistics.
	SetAsyncPhysicsTickEnabled(true);
}

void URoamVehicleMovement::InitFromDefinition(URoamCarDefinition* Definition)
{
	CarDefinition = Definition;
	if (Definition)
	{
		// The kinematic placeholder reaches roughly the top speed of the estimator; the physics model ignores this value.
		const FRoamCarPerformance Performance = Definition->ComputePerformance(FRoamPerformanceRules());
		PlaceholderTopSpeedKmh = FMath::Clamp(Performance.TopSpeedKmh, 80.0f, 320.0f);
	}
	RebuildPhysicsConfig();
	if (bUsePhysicsModel)
	{
		EnsureBodyReady();
		SetSimMode(ERoamVehicleSimMode::Physics);
	}
	ResetState(false);
}

void URoamVehicleMovement::SetSimMode(ERoamVehicleSimMode NewMode)
{
	if (SimMode == NewMode)
	{
		return;
	}
	SimMode = NewMode;
	if (OwnerVehicle && OwnerVehicle->Body)
	{
		if (NewMode == ERoamVehicleSimMode::KinematicPlaceholder)
		{
			// the placeholder moves the actor itself: the rigid body must not fight it
			OwnerVehicle->Body->SetSimulatePhysics(false);
			bPhysicsReady = false;
			bBodyConfigured = false;
		}
		else if (!bBodyConfigured)
		{
			EnsureBodyReady();
		}
	}
	UE_LOG(LogRoamVehicle, Display, TEXT("Vehicle sim mode -> %s"), *Roam::EnumToString(NewMode));
}

void URoamVehicleMovement::ShiftUp()
{
	++ManualGearRequest;
	Drivetrain.RequestShift(1);
}

void URoamVehicleMovement::ShiftDown()
{
	--ManualGearRequest;
	Drivetrain.RequestShift(-1);
}

void URoamVehicleMovement::SetAssists(const FRoamAssistSettings& NewAssists)
{
	Assists = NewAssists;
}

void URoamVehicleMovement::SetAssist(ERoamAssist Assist, bool bEnabled)
{
	Assists.Set(Assist, bEnabled);
}

void URoamVehicleMovement::SetTuning(const FRoamTuning& NewTuning)
{
	Tuning = NewTuning;
	// Rebuilds gear ratios (FinalDriveMultiplier, GearSpacing), spring/damper/anti-roll scales, ride height, brake balance, aero levels
	// and the differential locks; the mapping table is in Docs/Tech/DRIVE_TESTS.md "Tuning".
	RebuildPhysicsConfig();
}

void URoamVehicleMovement::SetUpgrades(const TMap<FName, int32>& NewUpgrades)
{
	Upgrades = NewUpgrades;
	RebuildPhysicsConfig();
	if (bBodyConfigured)
	{
		EnsureBodyReady();   // the mass may have changed (Platform.Weight)
	}
}

void URoamVehicleMovement::ResetState(bool bKeepVelocity)
{
	if (!bKeepVelocity)
	{
		PlaceholderForwardSpeed = 0.0f;
		PlaceholderVerticalSpeed = 0.0f;
		LastVelocityCmS = FVector::ZeroVector;
	}
	ManualGearRequest = 1;
	AirTime = 0.0f;
	bHaveLastLocation = false;
	const float KeepDistance = Telemetry.DistanceKm;
	Telemetry = FRoamVehicleTelemetry();
	Telemetry.DistanceKm = KeepDistance;
	Telemetry.RPM = CarDefinition ? CarDefinition->Engine.IdleRPM : 900.0f;
	ResetPhysicsState(bKeepVelocity);
}

void URoamVehicleMovement::NotifyTeleported()
{
	bHaveLastLocation = false;
	PlaceholderVerticalSpeed = 0.0f;
	bHaveStepData = false;
}

void URoamVehicleMovement::RestoreForwardSpeed(float ForwardSpeedCmS)
{
	PlaceholderForwardSpeed = ForwardSpeedCmS;
	if (SimMode == ERoamVehicleSimMode::Physics && OwnerVehicle && OwnerVehicle->Body && OwnerVehicle->Body->IsSimulatingPhysics())
	{
		OwnerVehicle->Body->SetPhysicsLinearVelocity(OwnerVehicle->Body->GetForwardVector() * ForwardSpeedCmS);
		for (int32 i = 0; i < Roam::NumWheels; ++i)
		{
			Wheels[i].Omega = ForwardSpeedCmS * 0.01f / WheelCfg[i].RadiusM;
		}
	}
}

void URoamVehicleMovement::ApplyInputFilter(float DeltaTime)
{
	if (!bFilterInputs)
	{
		Throttle = ThrottleInput;
		Brake = BrakeInput;
		Steer = SteerInput;
		Handbrake = HandbrakeInput;
		return;
	}
	const auto Approach = [DeltaTime](float Current, float Target, float RiseRate, float FallRate)
	{
		// Moving away from zero is "rise"; returning to zero or crossing to the other side is "fall".
		const bool bRising = FMath::Abs(Target) > FMath::Abs(Current) && (Current * Target >= 0.0f);
		return FMath::FInterpConstantTo(Current, Target, DeltaTime, bRising ? RiseRate : FallRate);
	};
	Steer = Approach(Steer, SteerInput, SteerRiseRate, SteerFallRate);
	Throttle = Approach(Throttle, ThrottleInput, PedalRiseRate, PedalFallRate);
	Brake = Approach(Brake, BrakeInput, PedalRiseRate, PedalFallRate);
	Handbrake = HandbrakeInput;
}

void URoamVehicleMovement::TickComponent(float DeltaTime, ELevelTick TickType, FActorComponentTickFunction* ThisTickFunction)
{
	Super::TickComponent(DeltaTime, TickType, ThisTickFunction);
	if (DeltaTime <= 0.0f || !GetOwner())
	{
		return;
	}

	ApplyInputFilter(DeltaTime);

	if (SimMode == ERoamVehicleSimMode::KinematicPlaceholder)
	{
		TickPlaceholder(DeltaTime);
	}
	else
	{
		TickPhysicsGameThread(DeltaTime);   // the physical telemetry is written by StepPhysics at every solver step
	}

	if (OwnerVehicle)
	{
		OwnerVehicle->PublishTelemetry(DeltaTime);
	}
}

void URoamVehicleMovement::AsyncPhysicsTickComponent(float DeltaTime, float SimTime)
{
	Super::AsyncPhysicsTickComponent(DeltaTime, SimTime);

	StepStats.NumSteps += 1;
	StepStats.TotalDt += DeltaTime;
	StepStats.MinDt = FMath::Min(StepStats.MinDt, DeltaTime);
	StepStats.MaxDt = FMath::Max(StepStats.MaxDt, DeltaTime);
	StepStats.LastSimTime = SimTime;

	if (SimMode == ERoamVehicleSimMode::Physics)
	{
		StepPhysics(DeltaTime, SimTime);
	}
}

// ------------------------------------------------------------------------------------------------------------------
// Placeholder: kinematic bicycle model that follows the ground
// ------------------------------------------------------------------------------------------------------------------

void URoamVehicleMovement::UpdatePlaceholderGear(float SpeedKmh)
{
	const URoamCarDefinition* Def = CarDefinition;
	const int32 NumGears = Def ? FMath::Max(1, Def->Gearbox.GetNumForwardGears()) : 6;
	const float Idle = Def ? Def->Engine.IdleRPM : 900.0f;
	const float Redline = Def ? Def->Engine.RedlineRPM : 6800.0f;
	const float TopPerGear = FMath::Max(PlaceholderTopSpeedKmh * 0.95f / static_cast<float>(NumGears), 5.0f);

	int32 Gear;
	if (Telemetry.bReversing)
	{
		Gear = -1;
	}
	else if (!Assists.bAutomaticGearbox)
	{
		ManualGearRequest = FMath::Clamp(ManualGearRequest, 1, NumGears);
		Gear = ManualGearRequest;
	}
	else if (SpeedKmh < 1.5f && Throttle < 0.05f)
	{
		Gear = 0;
	}
	else
	{
		Gear = FMath::Clamp(FMath::CeilToInt(SpeedKmh / TopPerGear), 1, NumGears);
	}
	Telemetry.Gear = Gear;

	float NormalisedSpeedInGear = 0.0f;
	if (Gear > 0)
	{
		NormalisedSpeedInGear = FMath::Clamp(SpeedKmh / (TopPerGear * static_cast<float>(Gear)), 0.0f, 1.05f);
	}
	else if (Gear < 0)
	{
		NormalisedSpeedInGear = FMath::Clamp(SpeedKmh / 40.0f, 0.0f, 1.0f);
	}
	const float Load = FMath::Max(Throttle, 0.0f);
	const float TargetRPM = Idle + (Redline - Idle) * FMath::Clamp(NormalisedSpeedInGear * 0.85f + 0.12f * Load, 0.0f, 1.0f) + (NormalisedSpeedInGear > 1.0f ? (NormalisedSpeedInGear - 1.0f) * 2000.0f : 0.0f);
	Telemetry.RPM = FMath::FInterpTo(Telemetry.RPM, TargetRPM, GetWorld() ? GetWorld()->GetDeltaSeconds() : 0.016f, 12.0f);
	Telemetry.NormRPM = Redline > 1.0f ? Telemetry.RPM / Redline : 0.0f;
	Telemetry.bRedline = Telemetry.NormRPM > 0.97f;
}

void URoamVehicleMovement::TickPlaceholder(float Dt)
{
	AActor* Owner = GetOwner();
	UWorld* World = GetWorld();
	if (!Owner || !World)
	{
		return;
	}

	const URoamCarDefinition* Def = CarDefinition;
	const float WheelbaseCm = Def ? Def->Geometry.WheelbaseCm : 260.0f;
	const float MaxSteerDeg = Def ? Def->Steering.MaxSteerAngleDeg : 34.0f;
	const float TopCmS = Roam::KmhToCms(PlaceholderTopSpeedKmh);
	const float PrevForwardSpeed = PlaceholderForwardSpeed;

	// ---- longitudinal ----------------------------------------------------------------------------------------------
	float Speed = PlaceholderForwardSpeed;
	float Accel = 0.0f;
	if (Throttle > 0.0f && Speed > -60.0f)
	{
		const float Ratio = FMath::Clamp(Speed / TopCmS, 0.0f, 1.0f);
		Accel += Throttle * 650.0f * (1.0f - Ratio * Ratio);
	}
	if (Brake > 0.0f)
	{
		if (Speed > 40.0f)
		{
			Accel -= Brake * 1000.0f;
		}
		else if (Throttle < 0.05f && Speed > -1100.0f)
		{
			Accel -= Brake * 350.0f; // reverse
		}
	}
	if (Speed > 0.0f)
	{
		Accel -= 40.0f + (Throttle < 0.05f ? 90.0f : 0.0f) + Handbrake * 900.0f;
	}
	else if (Speed < 0.0f)
	{
		Accel += 40.0f + (Brake < 0.05f ? 120.0f : 0.0f);
	}
	const float NewSpeed = Speed + Accel * Dt;
	// Do not let drag/brakes push the car through zero into reverse by themselves.
	if ((Speed > 0.0f && NewSpeed < 0.0f && Brake < 0.05f) || (Speed < 0.0f && NewSpeed > 0.0f && Throttle < 0.05f))
	{
		Speed = 0.0f;
	}
	else
	{
		Speed = NewSpeed;
	}
	PlaceholderForwardSpeed = Speed;

	// ---- steering / yaw --------------------------------------------------------------------------------------------
	const float SpeedKmh = Roam::CmsToKmh(FMath::Abs(Speed));
	const float LockFraction = Def ? Def->Steering.GetLockFraction(SpeedKmh) : FMath::Clamp(1.0f - SpeedKmh / 260.0f, 0.2f, 1.0f);
	const float RoadWheelDeg = Steer * MaxSteerDeg * LockFraction;
	const float YawRateRad = (Speed / FMath::Max(WheelbaseCm, 100.0f)) * FMath::Tan(FMath::DegreesToRadians(RoadWheelDeg));

	FRotator Rotation = Owner->GetActorRotation();
	const float NewYaw = Rotation.Yaw + FMath::RadiansToDegrees(YawRateRad) * Dt;
	const FVector Flat(FMath::Cos(FMath::DegreesToRadians(NewYaw)), FMath::Sin(FMath::DegreesToRadians(NewYaw)), 0.0f);

	// ---- position + ground follow ----------------------------------------------------------------------------------
	FVector Location = Owner->GetActorLocation();
	Location += Flat * Speed * Dt;

	FHitResult Hit;
	FCollisionQueryParams Params(SCENE_QUERY_STAT(RoamPlaceholderGround), false, Owner);
	Params.bReturnPhysicalMaterial = true;
	const FVector TraceStart = Location + FVector(0.0f, 0.0f, 150.0f);
	const FVector TraceEnd = Location - FVector(0.0f, 0.0f, 600.0f);
	const bool bHit = World->LineTraceSingleByChannel(Hit, TraceStart, TraceEnd, RoamCollision::TraceWheel, Params);

	bool bOnGround = false;
	FVector Normal = FVector::UpVector;
	ERoamSurface Surface = Telemetry.Surface;
	if (bHit)
	{
		const float GroundZ = static_cast<float>(Hit.ImpactPoint.Z);
		const float Gap = static_cast<float>(Location.Z) - GroundZ;
		if (Gap <= 20.0f && PlaceholderVerticalSpeed <= 50.0f)
		{
			Location.Z = GroundZ;
			PlaceholderVerticalSpeed = 0.0f;
			bOnGround = true;
		}
		else
		{
			PlaceholderVerticalSpeed -= 980.0f * Dt;
			Location.Z += PlaceholderVerticalSpeed * Dt;
			if (Location.Z <= GroundZ)
			{
				Location.Z = GroundZ;
				PlaceholderVerticalSpeed = 0.0f;
				bOnGround = true;
			}
		}
		Normal = FVector(Hit.ImpactNormal);
		Surface = GetDefault<URoamSettings>()->ResolveSurface(Hit.PhysMaterial.Get());
	}
	else
	{
		PlaceholderVerticalSpeed -= 980.0f * Dt;
		Location.Z += PlaceholderVerticalSpeed * Dt;
	}

	// ---- orientation: heading from the steering model, up from the ground normal (smoothed) -------------------------
	const FVector UpTarget = bOnGround ? Normal : FVector::UpVector;
	const FVector ForwardOnPlane = (Flat - UpTarget * FVector::DotProduct(Flat, UpTarget)).GetSafeNormal();
	const FQuat Target = FRotationMatrix::MakeFromXZ(ForwardOnPlane, UpTarget).ToQuat();
	const FQuat Current = Owner->GetActorQuat();
	const FQuat NewQuat = FQuat::Slerp(Current, Target, 1.0f - FMath::Exp(-14.0f * Dt));
	Owner->SetActorLocationAndRotation(Location, NewQuat, false, nullptr, ETeleportType::None);

	// ---- telemetry --------------------------------------------------------------------------------------------------
	Telemetry.bReversing = Speed < -15.0f;
	Telemetry.SpeedMs = FMath::Abs(Speed) * 0.01f;
	Telemetry.SpeedKmh = SpeedKmh;
	Telemetry.Throttle = Throttle;
	Telemetry.Brake = Brake;
	Telemetry.Steer = Steer;
	Telemetry.Handbrake = Handbrake;
	Telemetry.Surface = Surface;
	Telemetry.FrontWheelAngleDeg = RoadWheelDeg;
	Telemetry.YawRateDeg = FMath::RadiansToDegrees(YawRateRad);
	Telemetry.LongG = (Speed - PrevForwardSpeed) / Dt / 981.0f;
	Telemetry.LatG = Speed * YawRateRad / 981.0f;
	Telemetry.VertG = 1.0f;
	Telemetry.VelocityCmS = Flat * Speed + FVector(0.0f, 0.0f, PlaceholderVerticalSpeed);
	Telemetry.ForwardAxis = ForwardOnPlane;
	Telemetry.UpAxis = UpTarget;
	Telemetry.BodySlipAngleDeg = 0.0f;
	const FRotator Final = NewQuat.Rotator();
	Telemetry.PitchDeg = Final.Pitch;
	Telemetry.RollDeg = Final.Roll;
	Telemetry.DistanceKm += FMath::Abs(Speed) * Dt / 100000.0f;

	AirTime = bOnGround ? 0.0f : AirTime + Dt;
	Telemetry.AirTimeSec = AirTime;
	Telemetry.bAirborne = AirTime > 0.1f;
	Telemetry.NumWheelsOnGround = bOnGround ? 4 : 0;
	const float WheelLoad = (Def ? Def->MassKg : 1300.0f) * 9.81f * 0.25f;
	for (int32 i = 0; i < Roam::NumWheels; ++i)
	{
		Telemetry.WheelOnGround[i] = bOnGround;
		Telemetry.WheelLoadN[i] = bOnGround ? WheelLoad : 0.0f;
		Telemetry.WheelSlipRatio[i] = 0.0f;
		Telemetry.WheelSlipAngleDeg[i] = 0.0f;
	}
	Telemetry.bTCSActive = false;
	Telemetry.bSTMActive = false;
	Telemetry.bABSActive = Assists.bABS && Brake > 0.9f && SpeedKmh > 20.0f;
	if (const URoamTimeWeatherSubsystem* TimeWeather = World->GetSubsystem<URoamTimeWeatherSubsystem>())
	{
		Telemetry.SurfaceWetness = TimeWeather->GetWetness();
	}
	UpdatePlaceholderGear(SpeedKmh);
}

// ------------------------------------------------------------------------------------------------------------------
// Console: phys  (verifies the fixed-step physics callback)
// ------------------------------------------------------------------------------------------------------------------

ROAM_REGISTER_CONSOLE_COMMAND_CATEGORY("phys", "phys [reset|wheels]", "Print the fixed-step physics callback statistics of the player car (steps, Hz, dt).", "debug",
	[](const FRoamConsoleContext& Ctx) -> FString
	{
		ARoamVehicle* Vehicle = ARoamVehicle::GetPlayerVehicle(Ctx.World);
		if (!Vehicle || !Vehicle->VehicleMovement)
		{
			return Ctx.Fail(TEXT("no player vehicle"));
		}
		URoamVehicleMovement* Movement = Vehicle->VehicleMovement;
		if (Ctx.NumArgs() > 0 && Ctx.Arg(0).Equals(TEXT("reset"), ESearchCase::IgnoreCase))
		{
			Movement->ResetPhysicsStepStats();
			return TEXT("physics step statistics reset");
		}
		if (Ctx.NumArgs() > 0 && Ctx.Arg(0).Equals(TEXT("wheels"), ESearchCase::IgnoreCase))
		{
			const FString Wheels = Movement->DescribeWheels();
			UE_LOG(LogRoamVehicle, Display, TEXT("ROAM_PHYS_WHEELS %s"), *Wheels);
			return Wheels;
		}
		const FRoamPhysicsStepStats& Stats = Movement->GetPhysicsStepStats();
		const FString Text = FString::Printf(TEXT("ROAM_PHYS_STEPS steps=%lld avgHz=%.1f avgDt=%.5f minDt=%.5f maxDt=%.5f simTime=%.3f mode=%s"),
			Stats.NumSteps, Stats.GetAverageHz(), Stats.GetAverageDt(), Stats.NumSteps > 0 ? Stats.MinDt : 0.0f, Stats.MaxDt, Stats.LastSimTime,
			*Roam::EnumToString(Movement->GetSimMode()));
		UE_LOG(LogRoamVehicle, Display, TEXT("%s"), *Text);
		return Text;
	});
