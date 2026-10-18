// Copyright Epic Games, Inc. All Rights Reserved.

// Physics model of URoamVehicleMovement (SimMode == Physics): raycast suspension, normalised-slip tyres, engine/clutch/gearbox/diffs,
// brakes, aero, assists. Called once per Chaos solver step from AsyncPhysicsTickComponent (fixed 1/120 s, game thread with the
// physics thread parked). Everything inside is SI (m, N, Nm, kg, s); positions/velocities cross the Chaos boundary in cm.
// Documentation of the model and the tuning knobs: Docs/Tech/DRIVE_TESTS.md.

#include "Vehicle/RoamVehicleMovement.h"

#include "Components/StaticMeshComponent.h"
#include "Core/RoamCollision.h"
#include "Core/RoamLog.h"
#include "Core/RoamSettings.h"
#include "Data/RoamCarDefinition.h"
#include "Engine/StaticMesh.h"
#include "Engine/World.h"
#include "PhysicsEngine/BodyInstance.h"
#include "PhysicsEngine/BodySetup.h"
#include "Vehicle/RoamVehicle.h"
#include "Vehicle/RoamVehicleBody.h"
#include "World/RoamTimeWeatherSubsystem.h"

PRAGMA_DISABLE_DEPRECATION_WARNINGS
#include "Chaos/ParticleHandle.h"
#include "PhysicsProxy/SingleParticlePhysicsProxy.h"
PRAGMA_ENABLE_DEPRECATION_WARNINGS

namespace
{
	constexpr float Gravity = 9.81f;
	constexpr float AirDensity = 1.2f;
	constexpr float TyreV0 = 2.5f;           // slip regularisation speed (m/s)
	constexpr float RayMarginCm = 15.0f;     // rays start this far above the top of the travel (starts inside thin ground still hit)

	FORCEINLINE float SmoothStep(float A, float B, float X)
	{
		const float T = FMath::Clamp((X - A) / FMath::Max(B - A, 1.0e-4f), 0.0f, 1.0f);
		return T * T * (3.0f - 2.0f * T);
	}
}

// ------------------------------------------------------------------------------------------------------------------
// Setup
// ------------------------------------------------------------------------------------------------------------------

const URoamCarDefinition* URoamVehicleMovement::GetActiveDefinition() const
{
	if (CarDefinition)
	{
		return CarDefinition;
	}
	URoamVehicleMovement* Mutable = const_cast<URoamVehicleMovement*>(this);
	if (!Mutable->FallbackDefinition)
	{
		// Placeholder car (no definition): a plain 120 kW hatchback so the physics model always has a complete spec.
		URoamCarDefinition* Fallback = NewObject<URoamCarDefinition>(Mutable, NAME_None, RF_Transient);
		Fallback->CarId = TEXT("placeholder");
		Fallback->MassKg = 1250.0f;
		Fallback->Engine.IdleRPM = 850.0f;
		Fallback->Engine.RedlineRPM = 6800.0f;
		Fallback->Engine.RevLimiterRPM = 7000.0f;
		Fallback->Engine.TorqueCurve = FRoamEngineSpec::BuildSyntheticTorqueCurve(120.0f, 850.0f, 6800.0f);
		Fallback->Gearbox.FinalDrive = 4.1f;
		Fallback->Drivetrain.Layout = ERoamDrivetrain::FWD;
		Fallback->Drivetrain.FrontDiff = ERoamDiffType::Open;
		Fallback->Drivetrain.RearDiff = ERoamDiffType::Open;
		Mutable->FallbackDefinition = Fallback;
	}
	return Mutable->FallbackDefinition;
}

void URoamVehicleMovement::RebuildPhysicsConfig()
{
	const URoamCarDefinition* Def = GetActiveDefinition();
	const FRoamCarGeometry& Geo = Def->Geometry;

	// ---- upgrades -> scales (first-pass table, see Docs/Tech/DRIVE_TESTS.md "Upgrades") ----------------------------------------
	TorqueScale = 1.0f;
	GripScale = 1.0f;
	BrakeScale = 1.0f;
	AeroScale = 1.0f;
	float MassScale = 1.0f;
	float SpringScale = 1.0f;
	float ArbScale = 1.0f;
	float ShiftScale = 1.0f;
	for (const TPair<FName, int32>& Pair : Upgrades)
	{
		const float Tier = static_cast<float>(FMath::Max(Pair.Value, 0));
		const FString Slot = Pair.Key.ToString();
		if (Slot == TEXT("Engine.Tune")) { TorqueScale += 0.04f * Tier; }
		else if (Slot == TEXT("Engine.Intake") || Slot == TEXT("Engine.Exhaust")) { TorqueScale += 0.02f * Tier; }
		else if (Slot == TEXT("Platform.Brakes")) { BrakeScale += 0.06f * Tier; }
		else if (Slot == TEXT("Platform.Springs")) { SpringScale += 0.05f * Tier; }
		else if (Slot == TEXT("Platform.AntiRoll")) { ArbScale += 0.10f * Tier; }
		else if (Slot == TEXT("Platform.Weight")) { MassScale -= 0.03f * Tier; }
		else if (Slot == TEXT("Tires.Compound")) { GripScale += 0.04f * Tier; }
		else if (Slot == TEXT("Tires.Width")) { GripScale += 0.02f * Tier; }
		else if (Slot == TEXT("Drivetrain.Transmission")) { ShiftScale -= 0.15f * Tier; }
		else if (Slot == TEXT("Aero.Front") || Slot == TEXT("Aero.Rear")) { AeroScale += 0.04f * Tier; }
	}

	MassKg = FMath::Max(Def->MassKg * FMath::Max(MassScale, 0.7f), 300.0f);
	ComLocalCm = Def->CenterOfMassCm;

	const float FrontX = 0.5f * static_cast<float>(Geo.WheelFL.CenterCm.X + Geo.WheelFR.CenterCm.X);
	const float RearX = 0.5f * static_cast<float>(Geo.WheelRL.CenterCm.X + Geo.WheelRR.CenterCm.X);
	WheelbaseM = FMath::Max(0.01f * (FrontX - RearX), 1.0f);
	TrackFrontM = FMath::Max(0.01f * static_cast<float>(FMath::Abs(Geo.WheelFR.CenterCm.Y - Geo.WheelFL.CenterCm.Y)), 0.8f);
	const float FrontWeight = FMath::Clamp((static_cast<float>(ComLocalCm.X) - RearX) / FMath::Max(FrontX - RearX, 1.0f), 0.3f, 0.7f);

	float AverageRadius = 0.0f;
	for (int32 i = 0; i < Roam::NumWheels; ++i)
	{
		const FRoamWheelGeometry& Wheel = Geo.GetWheel(i);
		const bool bFront = i < 2;
		const FRoamSuspensionAxleSpec& Susp = bFront ? Def->SuspensionFront : Def->SuspensionRear;
		FRoamWheelCfg& Cfg = WheelCfg[i];
		Cfg.bFront = bFront;
		Cfg.bLeft = (i % 2) == 0;
		Cfg.RadiusM = FMath::Max(0.01f * Wheel.RadiusCm, 0.15f);
		AverageRadius += Cfg.RadiusM * 0.25f;
		Cfg.TravelUpM = 0.01f * FMath::Max(Susp.TravelUpCm, 1.0f);
		Cfg.TravelDownM = 0.01f * FMath::Max(Susp.TravelDownCm, 1.0f);
		Cfg.RestExtM = FMath::Clamp(Cfg.TravelUpM + 0.01f * Tuning.RideHeightOffsetCm, 0.01f, Cfg.TravelUpM + Cfg.TravelDownM - 0.005f);
		Cfg.HubRestLocalCm = Wheel.CenterCm;
		Cfg.MountLocalCm = Wheel.CenterCm + FVector(0.0, 0.0, Cfg.TravelUpM * 100.0);
		const float SpringTune = (bFront ? Tuning.SpringFrontScale : Tuning.SpringRearScale) * SpringScale;
		const float DampTune = bFront ? Tuning.DampingFrontScale : Tuning.DampingRearScale;
		const float ArbTune = (bFront ? Tuning.AntiRollFront : Tuning.AntiRollRear) / 30.0f * ArbScale;
		Cfg.Spring = Susp.SpringRateNPerM * SpringTune;
		Cfg.BumpDamp = Susp.BumpDampingNsPerM * DampTune;
		Cfg.ReboundDamp = Susp.ReboundDampingNsPerM * DampTune;
		Cfg.StopK = Susp.BumpStopNPerM;
		Cfg.ArbK = Susp.AntiRollNPerM * FMath::Clamp(ArbTune, 0.0f, 4.0f);
		Cfg.StaticLoadN = MassKg * Gravity * (bFront ? FrontWeight : 1.0f - FrontWeight) * 0.5f;
		Cfg.InertiaKgM2 = 11.0f * Cfg.RadiusM * Cfg.RadiusM;
		Cfg.StaticCamberDeg = bFront ? Tuning.CamberFrontDeg : Tuning.CamberRearDeg;
		Cfg.CamberGainDegPerM = Susp.CamberGainDegPerM;
		if (Wheels[i].ExtM <= 0.0f || !Wheels[i].bGrounded)
		{
			Wheels[i].ExtM = Cfg.RestExtM;
		}
	}
	TireShape[0] = RoamTire::MakeShape(Def->TireFront);
	TireShape[1] = RoamTire::MakeShape(Def->TireRear);

	BrakeBiasFront = Tuning.BrakeBalanceFrontPercent >= 0.0f ? FMath::Clamp(Tuning.BrakeBalanceFrontPercent * 0.01f, 0.3f, 0.85f) : Def->Brakes.BiasFront;
	RearShare = Tuning.CenterSplitRearPercent >= 0.0f ? FMath::Clamp(Tuning.CenterSplitRearPercent * 0.01f, 0.0f, 1.0f) : Def->Drivetrain.RearTorqueShare;

	Drivetrain.Configure(Def, Tuning, AverageRadius);
	Drivetrain.TorqueScale = TorqueScale;
}

void URoamVehicleMovement::EnsureBodyReady()
{
	bPhysicsReady = false;
	if (!OwnerVehicle)
	{
		OwnerVehicle = Cast<ARoamVehicle>(GetOwner());
	}
	URoamVehicleBody* Body = OwnerVehicle ? Cast<URoamVehicleBody>(OwnerVehicle->Body) : nullptr;
	if (!Body)
	{
		return;
	}
	const URoamCarDefinition* Def = GetActiveDefinition();
	const FRoamCarGeometry& Geo = Def->Geometry;

	// ---- collision shape: real hulls from the body mesh, else a box proxy sized like the car ------------------------------------
	UStaticMesh* Mesh = Body->GetStaticMesh();
	if (!Mesh || (Mesh == ProxyCubeMesh && ProxyCubeMesh))
	{
		if (!ProxyCubeMesh)
		{
			ProxyCubeMesh = LoadObject<UStaticMesh>(nullptr, TEXT("/Engine/BasicShapes/Cube.Cube"));
		}
		if (!ProxyCubeMesh)
		{
			UE_LOG(LogRoamVehicle, Error, TEXT("Vehicle physics: engine cube mesh missing, no collision proxy possible"));
			return;
		}
		if (Body->GetStaticMesh() != ProxyCubeMesh)
		{
			Body->SetStaticMesh(ProxyCubeMesh);
		}
		const float BoxHeight = FMath::Max(Geo.HeightCm * 0.55f, 40.0f);
		const FVector Size(Geo.LengthCm * 0.96f, FMath::Max(Geo.WidthCm * 0.92f, 100.0f), BoxHeight);
		const FVector Center(0.0, 0.0, Geo.RideHeightCm + 14.0f + BoxHeight * 0.5f);
		Body->SetProxyBox(Size, Center);
		Body->SetVisibility(false);
	}
	else
	{
		Body->ClearProxy();
		Body->SetVisibility(true);
	}

	// ---- rigid body properties --------------------------------------------------------------------------------------------------
	Body->SetCollisionProfileName(RoamCollision::ProfileVehicle);
	Body->SetEnableGravity(true);
	Body->SetSimulatePhysics(true);
	Body->SetLinearDamping(0.0f);
	Body->SetAngularDamping(0.02f);
	Body->SetNotifyRigidBodyCollision(true);
	Body->SetMassOverrideInKg(NAME_None, MassKg, true);
	FBodyInstance* BI = Body->GetBodyInstance();
	if (!BI || !BI->IsValidBodyInstance())
	{
		return;
	}
	BI->SetUseCCD(true);
	BI->SetInertiaConditioningEnabled(false);
	BI->SleepFamily = ESleepFamily::Custom;
	BI->CustomSleepThresholdMultiplier = 0.0f;
	// The raycast model applies its forces from the async tick of a body that may be asleep: a parked car that fell asleep never woke up
	// again (found in the L_Main integration run: full throttle, no motion). Chaos' per-particle switch keeps the body awake for good.
	if (Chaos::FSingleParticlePhysicsProxy* Proxy = BI->GetPhysicsActor())
	{
		Proxy->GetGameThreadAPI().SetSleepType(Chaos::ESleepType::NeverSleep);
	}

	// centre of mass: nudge the computed one onto the car definition's
	Body->SetCenterOfMass(FVector::ZeroVector);
	BI->InertiaTensorScale = FVector::OneVector;
	BI->UpdateMassProperties();
	const FVector ComputedWorld = BI->GetCOMPosition();
	const FVector ComputedLocal = Body->GetComponentTransform().InverseTransformPosition(ComputedWorld);
	Body->SetCenterOfMass(ComLocalCm - ComputedLocal);

	// inertia: scale the computed principal moments (kg cm^2) onto the estimated ones (kg m^2 -> kg cm^2)
	const FVector Computed = Body->GetInertiaTensor();
	const FVector Wanted = Def->GetEstimatedInertia() * 10000.0 * (MassKg / FMath::Max(Def->MassKg, 1.0f));
	BI->InertiaTensorScale = FVector(
		FMath::Clamp(Wanted.X / FMath::Max(Computed.X, 1.0), 0.02, 50.0),
		FMath::Clamp(Wanted.Y / FMath::Max(Computed.Y, 1.0), 0.02, 50.0),
		FMath::Clamp(Wanted.Z / FMath::Max(Computed.Z, 1.0), 0.02, 50.0));
	BI->UpdateMassProperties();
	// The hull-derived principal axes are not the car's axes (the computed tensor of the real hulls came out as roll > pitch), so a per-axis
	// scale in the principal frame cannot be trusted. Write the final mass properties on the physics proxy directly: principal frame = body
	// frame, wanted inertia (kg cm2), centre of mass of the definition.
	FRotator ComputedFrame = FRotator::ZeroRotator;
	if (Chaos::FSingleParticlePhysicsProxy* MassProxy = BI->GetPhysicsActor())
	{
		Chaos::FRigidBodyHandle_External& External = MassProxy->GetGameThreadAPI();
		ComputedFrame = FQuat(External.RotationOfMass()).Rotator();
		const Chaos::TVec3<Chaos::FRealSingle> InertiaCm2(static_cast<float>(Wanted.X), static_cast<float>(Wanted.Y), static_cast<float>(Wanted.Z));
		External.SetRotationOfMass(Chaos::FRotation3::FromIdentity());
		External.SetCenterOfMass(Chaos::FVec3(ComLocalCm));
		External.SetI(InertiaCm2);
		External.SetInvI(Chaos::TVec3<Chaos::FRealSingle>(1.0f / InertiaCm2.X, 1.0f / InertiaCm2.Y, 1.0f / InertiaCm2.Z));
	}
	UE_LOG(LogRoamVehicle, Display, TEXT("ROAM_VEHICLE_MASSFRAME principal frame of the hull tensor was (pitch %.1f yaw %.1f roll %.1f) deg; replaced by the body frame"), ComputedFrame.Pitch, ComputedFrame.Yaw, ComputedFrame.Roll);
	UE_LOG(LogRoamVehicle, Display, TEXT("ROAM_VEHICLE_BODY car=%s mass=%.0f kg comLocal=(%.1f %.1f %.1f) computedCom=(%.1f %.1f %.1f) inertia computed (%.3g %.3g %.3g) wanted (%.3g %.3g %.3g) kg cm2 scale=(%.2f %.2f %.2f) hulls=%d proxy=%d"),
		*Def->CarId.ToString(), MassKg, ComLocalCm.X, ComLocalCm.Y, ComLocalCm.Z, ComputedLocal.X, ComputedLocal.Y, ComputedLocal.Z, Computed.X, Computed.Y, Computed.Z, Wanted.X, Wanted.Y, Wanted.Z,
		BI->InertiaTensorScale.X, BI->InertiaTensorScale.Y, BI->InertiaTensorScale.Z, Body->GetBodySetup() ? Body->GetBodySetup()->AggGeom.ConvexElems.Num() : -1, Body->IsUsingProxy() ? 1 : 0);

	WheelQueryParams = FCollisionQueryParams(SCENE_QUERY_STAT(RoamWheelRay), false, OwnerVehicle);
	WheelQueryParams.bReturnPhysicalMaterial = true;

	if (!bHitDelegateBound)
	{
		Body->OnComponentHit.AddDynamic(this, &URoamVehicleMovement::OnBodyHit);
		bHitDelegateBound = true;
	}
	bBodyConfigured = true;
	bPhysicsReady = Body->IsSimulatingPhysics();
}

void URoamVehicleMovement::ResetPhysicsState(bool bKeepVelocity)
{
	for (int32 i = 0; i < Roam::NumWheels; ++i)
	{
		FRoamWheelState& W = Wheels[i];
		W = FRoamWheelState();
		W.ExtM = WheelCfg[i].RestExtM;
		if (bKeepVelocity && OwnerVehicle && OwnerVehicle->Body)
		{
			const FVector Forward = OwnerVehicle->Body->GetForwardVector();
			const float FwdSpeed = static_cast<float>(OwnerVehicle->Body->GetPhysicsLinearVelocity() | Forward) * 0.01f;
			W.Omega = FwdSpeed / WheelCfg[i].RadiusM;
		}
	}
	Drivetrain.Reset();
	TcsFactor = 1.0f;
	SteerAngleDeg = 0.0f;
	StmBrakeLeft = StmBrakeRight = StmActiveTimer = 0.0f;
	WingDeploy01 = 0.0f;
	AirTimer = 0.0f;
	SmoothedAccelMs2 = FVector(0.0, 0.0, Gravity);
	bHaveStepData = false;
}

// ------------------------------------------------------------------------------------------------------------------
// Game-thread side
// ------------------------------------------------------------------------------------------------------------------

void URoamVehicleMovement::TickPhysicsGameThread(float DeltaTime)
{
	if (!OwnerVehicle || !OwnerVehicle->Body)
	{
		return;
	}
	UStaticMeshComponent* Body = OwnerVehicle->Body;
	if (!bBodyConfigured || !Body->IsSimulatingPhysics())
	{
		EnsureBodyReady();
	}
	FBodyInstance* BI = Body->GetBodyInstance();
	bPhysicsReady = bBodyConfigured && BI && BI->IsValidBodyInstance() && Body->IsSimulatingPhysics();
	if (!bPhysicsReady)
	{
		return;
	}
	if (!BI->IsInstanceAwake())
	{
		BI->WakeInstance();
	}

	if (const UWorld* World = GetWorld())
	{
		if (const URoamTimeWeatherSubsystem* TimeWeather = World->GetSubsystem<URoamTimeWeatherSubsystem>())
		{
			CachedWetness = TimeWeather->GetWetness();
		}
	}
	Telemetry.SurfaceWetness = CachedWetness;

	// wheel visuals: suspension travel (the visuals component owns rotation / steer / spin)
	for (int32 i = 0; i < Roam::NumWheels && i < OwnerVehicle->WheelMeshes.Num(); ++i)
	{
		UStaticMeshComponent* WheelMesh = OwnerVehicle->WheelMeshes[i];
		if (WheelMesh)
		{
			const FRoamWheelCfg& Cfg = WheelCfg[i];
			FVector Location = Cfg.HubRestLocalCm;
			Location.Z = Cfg.MountLocalCm.Z - Wheels[i].ExtM * 100.0f;
			WheelMesh->SetRelativeLocation(Location);
		}
	}
	(void)DeltaTime;
}

void URoamVehicleMovement::OnBodyHit(UPrimitiveComponent* HitComponent, AActor* OtherActor, UPrimitiveComponent* OtherComponent, FVector NormalImpulse, const FHitResult& Hit)
{
	(void)HitComponent;
	const float ImpulseCmKgS = static_cast<float>(NormalImpulse.Size());
	const float DeltaVMs = 0.01f * ImpulseCmKgS / FMath::Max(MassKg, 1.0f);
	if (DeltaVMs < 1.5f)
	{
		return;
	}
	if (DeltaVMs >= 3.0f)
	{
		// what did the car hit? (integration pass: props / barriers / meshes with blocking collision on the road)
		static double LastHitLog = -10.0;
		const double Now = GetWorld() ? GetWorld()->GetTimeSeconds() : 0.0;
		if (Now - LastHitLog > 0.4)
		{
			LastHitLog = Now;
			const UStaticMeshComponent* OtherMesh = Cast<UStaticMeshComponent>(OtherComponent);
			UE_LOG(LogRoamVehicle, Display, TEXT("ROAM_VEHICLE_HIT other=%s comp=%s mesh=%s dv=%.1f speed=%.0f at=(%.0f %.0f %.0f) normal=(%.2f %.2f %.2f)"), OtherActor ? *OtherActor->GetName() : TEXT("-"), OtherComponent ? *OtherComponent->GetName() : TEXT("-"),
				OtherMesh && OtherMesh->GetStaticMesh() ? *OtherMesh->GetStaticMesh()->GetName() : TEXT("-"), DeltaVMs, Telemetry.SpeedKmh,
				Hit.ImpactPoint.X, Hit.ImpactPoint.Y, Hit.ImpactPoint.Z, Hit.ImpactNormal.X, Hit.ImpactNormal.Y, Hit.ImpactNormal.Z);
		}
	}
	Telemetry.LastImpactSpeedMs = DeltaVMs;
	Telemetry.LastImpactWorldTime = GetWorld() ? GetWorld()->GetTimeSeconds() : 0.0;
	if (OwnerVehicle)
	{
		OwnerVehicle->OnImpact.Broadcast(OwnerVehicle, DeltaVMs);
	}
}

FString URoamVehicleMovement::DescribeWheels() const
{
	static const TCHAR* Names[4] = { TEXT("FL"), TEXT("FR"), TEXT("RL"), TEXT("RR") };
	FString Out = FString::Printf(TEXT("gear %d rpm %.0f speed %.1f km/h tcs %.2f steer %.1f deg\n"), Drivetrain.Gear, Drivetrain.EngineRPM, Telemetry.SpeedKmh, TcsFactor, SteerAngleDeg);
	for (int32 i = 0; i < Roam::NumWheels; ++i)
	{
		const FRoamWheelState& W = Wheels[i];
		Out += FString::Printf(TEXT("%s ground=%d surf=%s Fz=%.0f Fx=%.0f Fy=%.0f kappa=%.3f alpha=%.1f slide=%.2f omega=%.1f comp=%.1fcm\n"), Names[i], W.bGrounded ? 1 : 0,
			*Roam::EnumToString(W.Surface), W.Fz, W.Fx, W.Fy, W.SlipRatio, FMath::RadiansToDegrees(W.SlipAngleRad), W.SlideNorm, W.Omega, W.CompressionM * 100.0f);
	}
	return Out;
}

// ------------------------------------------------------------------------------------------------------------------
// The solver step
// ------------------------------------------------------------------------------------------------------------------

void URoamVehicleMovement::StepPhysics(float Dt, float SimTime)
{
	(void)SimTime;
	if (!bPhysicsReady || !OwnerVehicle || Dt <= 1.0e-5f)
	{
		return;
	}
	UStaticMeshComponent* Body = OwnerVehicle->Body;
	UWorld* World = GetWorld();
	FBodyInstance* BI = Body ? Body->GetBodyInstance() : nullptr;
	if (!BI || !World)
	{
		return;
	}
	FBodyInstanceAsyncPhysicsTickHandle Handle = BI->GetBodyInstanceAsyncPhysicsTickHandle();
	if (!Handle)
	{
		return;
	}
	Chaos::FRigidBodyHandle_Internal* PT = Handle.operator->();
	if (!PT || PT->ObjectState() != Chaos::EObjectStateType::Dynamic)
	{
		return;
	}
	const URoamCarDefinition* Def = GetActiveDefinition();
	const URoamSettings* Settings = GetDefault<URoamSettings>();

	// ---- state of the body -------------------------------------------------------------------------------------------------------
	const FVector Xcm = PT->X();
	const FQuat Rot = PT->R();
	const FVector ComCm = Xcm + Rot.RotateVector(PT->CenterOfMass());
	const FVector VelCm = PT->V();
	const FVector Omega = PT->W();
	const FVector Fwd = Rot.GetAxisX();
	const FVector Right = Rot.GetAxisY();
	const FVector Up = Rot.GetAxisZ();
	const FVector VelMs = VelCm * 0.01;
	const float FwdSpeed = static_cast<float>(VelMs | Fwd);
	const float LatSpeed = static_cast<float>(VelMs | Right);
	const float Speed = static_cast<float>(VelMs.Size());
	const float YawRate = static_cast<float>(Omega | Up);   // rad/s, positive = turning right

	FVector TotalForceN = FVector::ZeroVector;   // accumulated for the sanity check only
	const auto AddForce = [&](const FVector& ForceN, const FVector& PointCm)
	{
		const FVector ForceChaos = ForceN * 100.0;
		PT->AddForce(ForceChaos);
		PT->AddTorque((PointCm - ComCm) ^ ForceChaos);
		TotalForceN += ForceN;
	};

	// ---- driver inputs ----------------------------------------------------------------------------------------------------------
	const bool bReverse = Drivetrain.Gear < 0;
	const float DrivePedal = bReverse ? Brake : Throttle;
	const float BrakePedal = bReverse ? Throttle : Brake;

	// ---- steering ---------------------------------------------------------------------------------------------------------------
	const float SpeedKmh = Speed * 3.6f;
	const float MaxSteer = Def->Steering.MaxSteerAngleDeg;
	const float LockFraction = Def->Steering.GetLockFraction(SpeedKmh);
	float TargetDeg = Steer * MaxSteer * LockFraction;
	float AssistDeg = 0.0f;
	if (Assists.SteeringAssist > 0.01f && Speed > 6.0f && Handbrake < 0.3f && FwdSpeed > 0.0f)
	{
		const float BetaDeg = FMath::RadiansToDegrees(FMath::Atan2(LatSpeed, FMath::Max(FMath::Abs(FwdSpeed), 3.0f)));
		const float Amount = Assists.SteeringAssist * SmoothStep(2.0f, 14.0f, FMath::Abs(BetaDeg));
		AssistDeg = FMath::Clamp(BetaDeg * 0.7f, -MaxSteer * LockFraction, MaxSteer * LockFraction) * Amount;
		if (FMath::Abs(Steer) < 0.05f && Speed > 20.0f)
		{
			AssistDeg -= FMath::Clamp(FMath::RadiansToDegrees(YawRate) * 0.05f * Assists.SteeringAssist, -1.5f, 1.5f);   // steering damper
		}
	}
	TargetDeg = FMath::Clamp(TargetDeg + AssistDeg, -MaxSteer, MaxSteer);
	SteerAngleDeg = FMath::FInterpConstantTo(SteerAngleDeg, TargetDeg, Dt, Def->Steering.SteerRateDegPerSec * (bFilterInputs ? 1.0f : 1.4f));
	{
		// Ackermann: inner wheel turns more. Positive angle = right turn, the right wheel is then the inner one.
		const float DeltaRad = FMath::DegreesToRadians(SteerAngleDeg);
		float Left = DeltaRad;
		float RightAngle = DeltaRad;
		if (FMath::Abs(DeltaRad) > 1.0e-3f)
		{
			const float Radius = WheelbaseM / FMath::Tan(FMath::Abs(DeltaRad));
			const float Inner = FMath::Atan(WheelbaseM / FMath::Max(Radius - 0.5f * TrackFrontM, 0.5f));
			const float Outer = FMath::Atan(WheelbaseM / (Radius + 0.5f * TrackFrontM));
			const float Share = Def->Steering.Ackermann;
			const float InnerBlend = FMath::Lerp(FMath::Abs(DeltaRad), Inner, Share);
			const float OuterBlend = FMath::Lerp(FMath::Abs(DeltaRad), Outer, Share);
			const float Sign = DeltaRad > 0.0f ? 1.0f : -1.0f;
			Left = Sign * (DeltaRad > 0.0f ? OuterBlend : InnerBlend);
			RightAngle = Sign * (DeltaRad > 0.0f ? InnerBlend : OuterBlend);
		}
		Wheels[0].SteerRad = Left;
		Wheels[1].SteerRad = RightAngle;
		Wheels[2].SteerRad = 0.0f;
		Wheels[3].SteerRad = 0.0f;
	}

	// ---- wheel rays, suspension -------------------------------------------------------------------------------------------------
	FVector ContactCm[4];
	FVector Normal[4];
	float SuspForce[4] = { 0.0f, 0.0f, 0.0f, 0.0f };
	int32 NumGrounded = 0;
	for (int32 i = 0; i < Roam::NumWheels; ++i)
	{
		const FRoamWheelCfg& C = WheelCfg[i];
		FRoamWheelState& W = Wheels[i];
		const FVector MountCm = Xcm + Rot.RotateVector(C.MountLocalCm);
		const float RayLengthCm = (C.TravelUpM + C.TravelDownM + C.RadiusM) * 100.0f;
		FHitResult Hit;
		const bool bHit = World->LineTraceSingleByChannel(Hit, MountCm + Up * RayMarginCm, MountCm - Up * RayLengthCm, RoamCollision::TraceWheel, WheelQueryParams);
		bool bGround = false;
		if (bHit)
		{
			FVector N = FVector(Hit.ImpactNormal);
			if ((N | Up) < 0.0)
			{
				N = -N;
			}
			if ((N | Up) > 0.3)
			{
				const float ExtCm = (Hit.Distance - RayMarginCm) - C.RadiusM * 100.0f;
				W.ExtM = FMath::Max(ExtCm * 0.01f, -0.06f);
				ContactCm[i] = FVector(Hit.ImpactPoint);
				Normal[i] = N;
				W.Surface = Settings->ResolveSurface(Hit.PhysMaterial.Get());
				bGround = true;
			}
		}
		W.bGrounded = bGround;
		if (!bGround)
		{
			W.ExtM = FMath::Min(W.ExtM + 2.0f * Dt, C.TravelUpM + C.TravelDownM);   // relaxes to full droop
			ContactCm[i] = MountCm - Up * ((W.ExtM + C.RadiusM) * 100.0f);
			Normal[i] = Up;
		}
		W.CompressionM = C.RestExtM - W.ExtM;
		if (bGround)
		{
			++NumGrounded;
			const FVector VMount = VelMs + (Omega ^ ((MountCm - ComCm) * 0.01));
			const float VComp = -static_cast<float>(VMount | Up);
			float Fs = C.StaticLoadN + C.Spring * W.CompressionM + (VComp > 0.0f ? C.BumpDamp : C.ReboundDamp) * VComp;
			if (W.CompressionM > C.TravelUpM)
			{
				Fs += C.StopK * (W.CompressionM - C.TravelUpM) + (VComp > 0.0f ? 0.5f * C.BumpDamp * VComp : 0.0f);
			}
			SuspForce[i] = Fs;
		}
	}
	// anti-roll bars
	for (int32 Axle = 0; Axle < 2; ++Axle)
	{
		const int32 L = Axle * 2;
		const int32 R = L + 1;
		const float CrL = FMath::Clamp(Wheels[L].CompressionM, -WheelCfg[L].TravelDownM, WheelCfg[L].TravelUpM);
		const float CrR = FMath::Clamp(Wheels[R].CompressionM, -WheelCfg[R].TravelDownM, WheelCfg[R].TravelUpM);
		const float Arb = WheelCfg[L].ArbK * (CrL - CrR);
		if (Wheels[L].bGrounded) { SuspForce[L] += Arb; }
		if (Wheels[R].bGrounded) { SuspForce[R] -= Arb; }
	}
	for (int32 i = 0; i < Roam::NumWheels; ++i)
	{
		FRoamWheelState& W = Wheels[i];
		if (W.bGrounded)
		{
			const float Fs = FMath::Clamp(SuspForce[i], 0.0f, 8.0f * MassKg * Gravity);
			W.Fz = Fs;
			const FRoamWheelCfg& C = WheelCfg[i];
			const FVector MountCm = Xcm + Rot.RotateVector(C.MountLocalCm);
			AddForce(Up * Fs, MountCm);
		}
		else
		{
			W.Fz = 0.0f;
		}
	}

	// ---- tyre contact kinematics ------------------------------------------------------------------------------------------------
	FVector DirF[4];
	FVector DirL[4];
	float VX[4], VY[4], Mu[4];
	for (int32 i = 0; i < Roam::NumWheels; ++i)
	{
		const FRoamWheelState& W = Wheels[i];
		if (!W.bGrounded)
		{
			DirF[i] = Fwd;
			DirL[i] = Right;
			VX[i] = VY[i] = Mu[i] = 0.0f;
			continue;
		}
		const FVector Vc = VelMs + (Omega ^ ((ContactCm[i] - ComCm) * 0.01));
		const FVector Heading = FQuat(Up, W.SteerRad).RotateVector(Fwd);
		const FVector N = Normal[i];
		DirF[i] = (Heading - N * (Heading | N)).GetSafeNormal();
		DirL[i] = (N ^ DirF[i]);
		VX[i] = static_cast<float>(Vc | DirF[i]);
		VY[i] = static_cast<float>(Vc | DirL[i]);
		const FRoamTireSpec& Spec = i < 2 ? Def->TireFront : Def->TireRear;
		Mu[i] = RoamTire::Mu(Spec, W.Fz, W.Surface, CachedWetness, i < 2 ? Tuning.TirePressureFrontPsi : Tuning.TirePressureRearPsi) * GripScale;
	}

	// ---- drivetrain: engine, gearbox, torque split ------------------------------------------------------------------------------
	const ERoamDrivetrain Layout = Def->Drivetrain.Layout;
	float Share[4] = { 0.0f, 0.0f, 0.0f, 0.0f };
	{
		float RearAxleShare = Layout == ERoamDrivetrain::RWD ? 1.0f : (Layout == ERoamDrivetrain::AWD ? RearShare : 0.0f);
		const float OmegaFront = 0.5f * (Wheels[0].Omega + Wheels[1].Omega);
		const float OmegaRear = 0.5f * (Wheels[2].Omega + Wheels[3].Omega);
		if (Layout == ERoamDrivetrain::AWD)
		{
			RearAxleShare = RoamDrive::CenterRearShare(Def->Drivetrain.CenterDiff, RearShare, Def->Drivetrain.CenterLock, OmegaFront, OmegaRear);
		}
		Share[0] = Share[1] = 0.5f * (1.0f - RearAxleShare);
		Share[2] = Share[3] = 0.5f * RearAxleShare;
	}
	float DrivenOmega = 0.0f;
	for (int32 i = 0; i < Roam::NumWheels; ++i)
	{
		DrivenOmega += Share[i] * Wheels[i].Omega;
	}
	FRoamDrivetrain::FInput DriveIn;
	DriveIn.DrivePedal = DrivePedal * (1.0f - 0.5f * FMath::Clamp(Handbrake, 0.0f, 1.0f));
	DriveIn.ThrottlePedal = Throttle;
	DriveIn.BrakePedal = Brake;
	DriveIn.ForwardSpeedMs = FwdSpeed;
	DriveIn.DrivenOmega = DrivenOmega;
	DriveIn.bAutomatic = Assists.bAutomaticGearbox;
	DriveIn.TcsFactor = Assists.bTractionControl ? TcsFactor : 1.0f;
	Drivetrain.Step(Dt, DriveIn);
	const float WheelTorque = Drivetrain.WheelTorqueNm;

	// differential torque bias per axle
	float Bias[4] = { 0.0f, 0.0f, 0.0f, 0.0f };
	for (int32 Axle = 0; Axle < 2; ++Axle)
	{
		const int32 L = Axle * 2;
		const int32 R = L + 1;
		const float AxleShare = Share[L] + Share[R];
		if (AxleShare < 1.0e-3f)
		{
			continue;
		}
		ERoamDiffType Type = Axle == 0 ? Def->Drivetrain.FrontDiff : Def->Drivetrain.RearDiff;
		float LockAccel = Axle == 0 ? Def->Drivetrain.FrontLockAccel : Def->Drivetrain.RearLockAccel;
		float LockDecel = Axle == 0 ? Def->Drivetrain.FrontLockDecel : Def->Drivetrain.RearLockDecel;
		if (Tuning.DiffAccelLock >= 0.0f)
		{
			LockAccel = Tuning.DiffAccelLock;
			if (Type == ERoamDiffType::Open) { Type = ERoamDiffType::LimitedSlip; }
		}
		if (Tuning.DiffDecelLock >= 0.0f)
		{
			LockDecel = Tuning.DiffDecelLock;
		}
		const float Preload = Type == ERoamDiffType::Open ? 0.0f : Def->Drivetrain.PreloadNm;
		const float X = RoamDrive::DiffBias(Type, LockAccel, LockDecel, Preload, AxleShare * WheelTorque, Wheels[L].Omega, Wheels[R].Omega);
		Bias[L] = -X;
		Bias[R] = X;
	}

	// ---- brakes (+ ABS, stability-control brake requests) -----------------------------------------------------------------------
	const float PeakBrakeForce = Def->Brakes.PeakDecelerationG * Gravity * MassKg * Tuning.BrakePressureScale * BrakeScale;
	bool bAbsActive = false;
	float BrakeTorque[4];
	// brake-force distribution: half the static bias (tuning), half the current axle load share, so that both axles reach the grip
	// limit together under load transfer (a fixed bias would lock the rear first and cap the stop at ~0.8 g)
	const float FzFrontAxle = Wheels[0].Fz + Wheels[1].Fz;
	const float FzRearAxle = Wheels[2].Fz + Wheels[3].Fz;
	const float DynamicFront = (FzFrontAxle + FzRearAxle) > 1000.0f ? FzFrontAxle / (FzFrontAxle + FzRearAxle) : BrakeBiasFront;
	const float EffectiveBiasFront = FMath::Lerp(BrakeBiasFront, DynamicFront, 0.5f);
	for (int32 i = 0; i < Roam::NumWheels; ++i)
	{
		FRoamWheelState& W = Wheels[i];
		const float Radius = WheelCfg[i].RadiusM;
		if (Assists.bABS && Def->Brakes.bHasABS && BrakePedal > 0.1f && W.bGrounded && Speed > 3.0f)
		{
			// proportional pressure modulation around the slip threshold (a bang-bang release loses a fifth of the braking force)
			const float Threshold = Def->Brakes.ABSSlipRatio * 0.9f;
			const float Excess = FMath::Clamp((-W.SlipRatio - Threshold) / (0.5f * Threshold), 0.0f, 1.0f);
			const float AbsTarget = 1.0f - 0.95f * Excess;
			W.AbsRelease = FMath::FInterpConstantTo(W.AbsRelease, AbsTarget, Dt, AbsTarget < W.AbsRelease ? 40.0f : 12.0f);
			bAbsActive |= (W.AbsRelease < 0.85f && BrakePedal > 0.3f);
		}
		else
		{
			W.AbsRelease = 1.0f;
		}
		const float AxleBias = i < 2 ? EffectiveBiasFront : 1.0f - EffectiveBiasFront;
		float Torque = BrakePedal * W.AbsRelease * PeakBrakeForce * AxleBias * 0.5f * Radius;
		if (i >= 2)
		{
			Torque += Handbrake * Def->Brakes.HandbrakeTorqueNm;
		}
		BrakeTorque[i] = Torque;
	}

	// stability control: brake the outer front wheel against oversteer
	bool bStmActive = false;
	{
		float WantLeft = 0.0f;
		float WantRight = 0.0f;
		if (Assists.bStabilityControl && Speed > 8.0f && Handbrake < 0.25f && NumGrounded >= 3 && FwdSpeed > 0.0f)
		{
			const float Delta = FMath::DegreesToRadians(SteerAngleDeg);
			const float Vref = FMath::Max(FwdSpeed, 3.0f);
			const float YawDesired = Vref * FMath::Tan(Delta) / (WheelbaseM * (1.0f + Vref * Vref / (45.0f * 45.0f)));
			float Over;
			if (YawDesired * YawRate >= 0.0f)
			{
				Over = FMath::Abs(YawRate) - FMath::Abs(YawDesired) * 1.15f - 0.07f;
			}
			else
			{
				Over = FMath::Abs(YawRate) - 0.07f;
			}
			if (Over > 0.0f)
			{
				const float Strength = Def->AssistDefaults.STMStrength;
				const float Brake01 = FMath::Min(Over * 9000.0f * (0.3f + Strength), 0.9f * PeakBrakeForce * BrakeBiasFront * 0.5f * WheelCfg[0].RadiusM);
				if (YawRate > 0.0f) { WantLeft = Brake01; } else { WantRight = Brake01; }   // outer front wheel
				StmActiveTimer = 0.25f;
			}
		}
		StmBrakeLeft = FMath::FInterpTo(StmBrakeLeft, WantLeft, Dt, WantLeft > StmBrakeLeft ? 40.0f : 12.0f);
		StmBrakeRight = FMath::FInterpTo(StmBrakeRight, WantRight, Dt, WantRight > StmBrakeRight ? 40.0f : 12.0f);
		StmActiveTimer = FMath::Max(0.0f, StmActiveTimer - Dt);
		bStmActive = StmActiveTimer > 0.0f;
		BrakeTorque[0] += StmBrakeLeft;
		BrakeTorque[1] += StmBrakeRight;
	}

	// ---- wheel dynamics (implicit in the tyre force, drive inertia shared through the clutch) -------------------------------------
	float A[4];
	float B[4];
	float Alpha[4];
	for (int32 i = 0; i < Roam::NumWheels; ++i)
	{
		const FRoamWheelCfg& C = WheelCfg[i];
		const FRoamWheelState& W = Wheels[i];
		float Fx0 = 0.0f;
		float K = 0.0f;
		if (W.bGrounded)
		{
			const RoamTire::FShape& Shape = TireShape[i < 2 ? 0 : 1];
			const RoamTire::FResult R0 = RoamTire::Evaluate(Shape, Mu[i], W.Fz, VX[i], VY[i], W.Omega * C.RadiusM, TyreV0);
			const RoamTire::FResult R1 = RoamTire::Evaluate(Shape, Mu[i], W.Fz, VX[i], VY[i], (W.Omega + 1.0f) * C.RadiusM, TyreV0);
			Fx0 = R0.Fx;
			K = FMath::Max(0.0f, R1.Fx - R0.Fx);
			// Beyond the grip peak the tangent stiffness is zero or negative and the implicit step would overshoot the zero-slip
			// speed and chatter (+-5 kN every step at standstill). The secant slope towards the zero-slip wheel speed never does.
			const float DeltaOmega = FMath::Abs(W.Omega - VX[i] / C.RadiusM);
			if (DeltaOmega > 1.0e-3f)
			{
				K = FMath::Max(K, FMath::Abs(Fx0) / DeltaOmega);
			}
		}
		A[i] = C.InertiaKgM2 + Dt * C.RadiusM * K;
		B[i] = Share[i] * WheelTorque + Bias[i] - C.RadiusM * Fx0;
	}
	float SumSB = 0.0f;
	float SumSS = 0.0f;
	for (int32 i = 0; i < Roam::NumWheels; ++i)
	{
		SumSB += Share[i] * B[i] / A[i];
		SumSS += Share[i] * Share[i] / A[i];
	}
	const float Ir = Drivetrain.ReflectedInertia;
	const float S = SumSB / (1.0f + Ir * SumSS);
	for (int32 i = 0; i < Roam::NumWheels; ++i)
	{
		Alpha[i] = (B[i] - Share[i] * Ir * S) / A[i];
		FRoamWheelState& W = Wheels[i];
		float OmegaFree = W.Omega + Dt * Alpha[i];
		const float Eff = A[i] + Ir * Share[i];
		const float Delta = Dt * BrakeTorque[i] / Eff;
		if (FMath::Abs(OmegaFree) <= Delta)
		{
			OmegaFree = 0.0f;
		}
		else
		{
			OmegaFree -= FMath::Sign(OmegaFree) * Delta;
		}
		if (!W.bGrounded)
		{
			OmegaFree *= (1.0f - 0.15f * Dt);
		}
		W.Omega = OmegaFree;
	}

	// ---- tyre forces on the body --------------------------------------------------------------------------------------------------
	float MaxDriveSlip = 0.0f;
	for (int32 i = 0; i < Roam::NumWheels; ++i)
	{
		FRoamWheelState& W = Wheels[i];
		if (!W.bGrounded)
		{
			W.Fx = W.Fy = 0.0f;
			W.SlipRatio = 0.0f;
			W.SlipAngleRad = 0.0f;
			W.SlideNorm = 0.0f;
			continue;
		}
		const FRoamWheelCfg& C = WheelCfg[i];
		const RoamTire::FResult R = RoamTire::Evaluate(TireShape[i < 2 ? 0 : 1], Mu[i], W.Fz, VX[i], VY[i], W.Omega * C.RadiusM, TyreV0);
		float Fx = R.Fx;
		float Fy = R.Fy;
		// the force may not reverse the slip velocity within one step
		const float SlipSpeed = FMath::Sqrt((VX[i] - W.Omega * C.RadiusM) * (VX[i] - W.Omega * C.RadiusM) + VY[i] * VY[i]);
		const float MaxForce = 0.3f * MassKg * SlipSpeed / Dt;
		const float ForceMag = FMath::Sqrt(Fx * Fx + Fy * Fy);
		if (ForceMag > MaxForce && ForceMag > 1.0e-3f)
		{
			const float Scale = MaxForce / ForceMag;
			Fx *= Scale;
			Fy *= Scale;
		}
		const RoamTire::FShape& Shape = TireShape[i < 2 ? 0 : 1];
		(void)Shape;
		const FRoamTireSpec& Spec = i < 2 ? Def->TireFront : Def->TireRear;
		const float RollingResistance = Spec.RollingResistance * RoamTire::RollingResistanceFactor(W.Surface) * W.Fz * FMath::Tanh(VX[i] / 0.4f);
		Fx -= RollingResistance;
		W.Fx = Fx;
		W.Fy = Fy;
		W.SlipRatio = R.SlipRatio;
		W.SlipAngleRad = R.SlipAngleRad;
		W.SlideNorm = R.SlideNorm;
		AddForce(DirF[i] * Fx + DirL[i] * Fy, ContactCm[i]);
		if (Share[i] > 0.0f)
		{
			MaxDriveSlip = FMath::Max(MaxDriveSlip, R.SlipRatio / TireShape[i < 2 ? 0 : 1].PeakSlipRatio);
		}
	}

	// ---- traction control -----------------------------------------------------------------------------------------------------------
	{
		// slip-targeting integrator: the torque factor falls while the driven wheels slip beyond ~1.1x the grip peak (faster the more
		// they exceed it) and creeps back once they are clearly below it, so the wheels settle near the peak instead of hunting.
		const float Strength = Def->AssistDefaults.TCSStrength;
		const float MinFactor = 1.0f - (0.35f + 0.6f * Strength);
		if (Assists.bTractionControl && DrivePedal > 0.05f)
		{
			float Loose = 0.0f;
			for (int32 i = 0; i < Roam::NumWheels; ++i)
			{
				if (Share[i] > 0.0f && Wheels[i].bGrounded)
				{
					Loose = FMath::Max(Loose, 1.0f - Roam::SurfaceGripMultiplier(Wheels[i].Surface, 0.0f));
				}
			}
			const float Excess = MaxDriveSlip - (1.1f + 1.5f * Loose);   // loose surfaces peak at larger slip: let the wheels slip more
			if (Excess > 0.0f)
			{
				TcsFactor -= Dt * (4.0f + 30.0f * FMath::Min(Excess, 3.0f)) * (0.5f + Strength);
			}
			else if (Excess < -0.2f)
			{
				TcsFactor += Dt * 1.5f;
			}
			TcsFactor = FMath::Clamp(TcsFactor, MinFactor, 1.0f);
		}
		else
		{
			TcsFactor = FMath::FInterpTo(TcsFactor, 1.0f, Dt, 8.0f);
		}
	}

	// ---- aerodynamics -----------------------------------------------------------------------------------------------------------------
	float Downforce = 0.0f;
	{
		const float Dynamic = 0.5f * AirDensity * Speed * Speed;
		if (Speed > 0.1f)
		{
			AddForce(-VelMs.GetSafeNormal() * (Dynamic * Def->Aero.CdA), ComCm);
		}
		const float WingTarget = (Def->Aero.bActiveWing && SpeedKmh > Def->Aero.ActiveWingDeployKmh) ? 1.0f : 0.0f;
		WingDeploy01 = FMath::FInterpTo(WingDeploy01, WingTarget, Dt, 3.0f);
		float AvgCompression = 0.0f;
		for (int32 i = 0; i < Roam::NumWheels; ++i)
		{
			AvgCompression += 0.25f * Wheels[i].CompressionM;
		}
		const float GroundEffect = 1.0f + Def->Aero.GroundEffect * FMath::Clamp(0.5f + AvgCompression / 0.06f, 0.0f, 1.5f);
		const float ClaFront = Def->Aero.ClAFront * Tuning.AeroFrontLevel * AeroScale * GroundEffect;
		const float ClaRear = (Def->Aero.ClARear * Tuning.AeroRearLevel + Def->Aero.ActiveWingExtraClA * WingDeploy01) * AeroScale * GroundEffect;
		const float DfFront = Dynamic * ClaFront;
		const float DfRear = Dynamic * ClaRear;
		Downforce = DfFront + DfRear;
		const FVector FrontPoint = Xcm + Rot.RotateVector(FVector(0.5 * (Def->Geometry.WheelFL.CenterCm.X + Def->Geometry.WheelFR.CenterCm.X), 0.0, ComLocalCm.Z));
		const FVector RearPoint = Xcm + Rot.RotateVector(FVector(0.5 * (Def->Geometry.WheelRL.CenterCm.X + Def->Geometry.WheelRR.CenterCm.X), 0.0, ComLocalCm.Z));
		if (DfFront > 0.0f) { AddForce(-Up * DfFront, FrontPoint); }
		if (DfRear > 0.0f) { AddForce(-Up * DfRear, RearPoint); }
	}

	// ---- air control: damp the spin and nose the car along its flight path so jumps land on the wheels ------------------------------
	AirTimer = NumGrounded == 0 ? AirTimer + Dt : 0.0f;
	if (AirTimer > 0.1f)
	{
		const FVector Inertia = Def->GetEstimatedInertia() * (MassKg / FMath::Max(Def->MassKg, 1.0f));
		const float WRoll = static_cast<float>(Omega | Fwd);
		const float WPitch = static_cast<float>(Omega | Right);
		const float WYaw = static_cast<float>(Omega | Up);
		const float HorizontalSpeed = static_cast<float>(FVector(VelMs.X, VelMs.Y, 0.0).Size());
		const float VelPitch = FMath::Atan2(static_cast<float>(VelMs.Z), FMath::Max(HorizontalSpeed, 1.0f));
		const float CarPitch = FMath::Asin(FMath::Clamp(static_cast<float>(Fwd.Z), -1.0f, 1.0f));
		const float CarRoll = FMath::Asin(FMath::Clamp(static_cast<float>(Right.Z), -1.0f, 1.0f));
		const float TauRoll = static_cast<float>(Inertia.X) * (-6.0f * CarRoll - 3.0f * WRoll);
		const float TauPitch = static_cast<float>(Inertia.Y) * (-6.0f * (VelPitch - CarPitch) - 3.0f * WPitch);
		const float TauYaw = static_cast<float>(Inertia.Z) * (-1.5f * WYaw);
		const FVector TorqueNm = Fwd * TauRoll + Right * TauPitch + Up * TauYaw;
		PT->AddTorque(TorqueNm * 10000.0);
	}

	// ---- sanity -------------------------------------------------------------------------------------------------------------------------
	if (!FMath::IsFinite(static_cast<float>(TotalForceN.X + TotalForceN.Y + TotalForceN.Z)))
	{
		if (!bNaNReported)
		{
			bNaNReported = true;
			UE_LOG(LogRoamVehicle, Error, TEXT("Vehicle physics produced a non-finite force; resetting the wheel state"));
		}
		for (FRoamWheelState& W : Wheels)
		{
			W.Omega = 0.0f;
		}
	}

	// ---- telemetry (physical quantities; the game-thread tick adds the rest) ---------------------------------------------------------
	{
		const FVector PrevVelMs = bHaveStepData ? LastStepVelocityCmS * 0.01 : VelMs;
		const FVector AccelWorld = (VelMs - PrevVelMs) / Dt;
		const FVector Proper = AccelWorld + FVector(0.0, 0.0, Gravity);
		const FVector ProperBody(Proper | Fwd, Proper | Right, Proper | Up);
		const float Blend = 1.0f - FMath::Exp(-Dt / 0.06f);
		SmoothedAccelMs2 = FMath::Lerp(SmoothedAccelMs2, ProperBody, Blend);
		LastStepVelocityCmS = VelCm;
		bHaveStepData = true;

		Telemetry.SpeedMs = Speed;
		Telemetry.SpeedKmh = SpeedKmh;
		Telemetry.RPM = Drivetrain.EngineRPM;
		Telemetry.NormRPM = Drivetrain.EngineRPM / FMath::Max(Def->Engine.RedlineRPM, 1.0f);
		Telemetry.Gear = Drivetrain.Gear;
		Telemetry.Throttle = Throttle;
		Telemetry.Brake = Brake;
		Telemetry.Steer = Steer;
		Telemetry.Handbrake = Handbrake;
		Telemetry.LongG = static_cast<float>(SmoothedAccelMs2.X) / Gravity;
		Telemetry.LatG = static_cast<float>(SmoothedAccelMs2.Y) / Gravity;
		Telemetry.VertG = static_cast<float>(SmoothedAccelMs2.Z) / Gravity;
		Telemetry.YawRateDeg = FMath::RadiansToDegrees(YawRate);
		Telemetry.bTCSActive = Assists.bTractionControl && TcsFactor < 0.92f && DrivePedal > 0.05f;
		Telemetry.bSTMActive = bStmActive;
		Telemetry.bABSActive = bAbsActive;
		Telemetry.bTurbo = Def->Engine.bTurbo;
		Telemetry.Boost01 = Drivetrain.Boost01;
		Telemetry.bRedline = Telemetry.NormRPM > 0.97f;
		Telemetry.DistanceKm += Speed * Dt * 0.001f;
		Telemetry.VelocityCmS = VelCm;
		Telemetry.ForwardAxis = Fwd;
		Telemetry.UpAxis = Up;
		Telemetry.NumWheelsOnGround = NumGrounded;
		Telemetry.bAirborne = AirTimer > 0.1f;
		Telemetry.AirTimeSec = AirTimer;
		Telemetry.BodySlipAngleDeg = Speed > 2.0f ? FMath::RadiansToDegrees(FMath::Atan2(LatSpeed, FMath::Abs(FwdSpeed))) : 0.0f;
		const FRotator Euler = Rot.Rotator();
		Telemetry.PitchDeg = static_cast<float>(Euler.Pitch);
		Telemetry.RollDeg = static_cast<float>(Euler.Roll);
		Telemetry.bReversing = FwdSpeed < -0.5f || Drivetrain.Gear < 0;
		Telemetry.bShifting = Drivetrain.bShifting;
		Telemetry.FrontWheelAngleDeg = FMath::RadiansToDegrees(0.5f * (Wheels[0].SteerRad + Wheels[1].SteerRad));
		Telemetry.bBrakeLightsOn = BrakePedal > 0.05f || Handbrake > 0.5f;
		Telemetry.EngineTorqueNm = Drivetrain.EngineTorqueNm;
		Telemetry.bClutchSlipping = Drivetrain.bSlipping;
		Telemetry.SteerAssistDeg = AssistDeg;
		Telemetry.DownforceN = Downforce;
		bool bSurfaceSet = false;
		for (int32 i = 0; i < Roam::NumWheels; ++i)
		{
			const FRoamWheelState& W = Wheels[i];
			const FRoamWheelCfg& C = WheelCfg[i];
			Telemetry.WheelSlipRatio[i] = W.SlipRatio;
			Telemetry.WheelSlipAngleDeg[i] = FMath::RadiansToDegrees(W.SlipAngleRad);
			Telemetry.WheelLoadN[i] = W.Fz;
			Telemetry.WheelOnGround[i] = W.bGrounded;
			Telemetry.WheelAngVelRadS[i] = W.Omega;
			Telemetry.WheelTravelCm[i] = W.CompressionM * 100.0f;
			Telemetry.WheelSteerDeg[i] = FMath::RadiansToDegrees(W.SteerRad);
			Telemetry.WheelCamberDeg[i] = C.StaticCamberDeg + C.CamberGainDegPerM * W.CompressionM;
			Telemetry.WheelSlideNorm[i] = W.SlideNorm;
			Telemetry.WheelSurface[i] = W.Surface;
			if (W.bGrounded && !bSurfaceSet)
			{
				Telemetry.Surface = W.Surface;
				bSurfaceSet = true;
			}
		}
	}
}
