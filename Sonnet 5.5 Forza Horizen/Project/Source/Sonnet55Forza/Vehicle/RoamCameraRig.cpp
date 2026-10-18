// Copyright Epic Games, Inc. All Rights Reserved.

#include "Vehicle/RoamCameraRig.h"

#include "Core/RoamCollision.h"
#include "Data/RoamCarDefinition.h"
#include "Engine/World.h"
#include "Vehicle/RoamVehicle.h"

URoamCameraRig::URoamCameraRig()
{
	PrimaryComponentTick.bCanEverTick = true;
	PrimaryComponentTick.bStartWithTickEnabled = true;
	// After physics and after the vehicle movement ticked, so the camera sees this frame's car transform.
	PrimaryComponentTick.TickGroup = TG_PostPhysics;

	bUsePawnControlRotation = false;
	FieldOfView = ChaseBaseFov;
	// World-space driven (see class comment).
	SetAbsolute(true, true, false);
}

ARoamVehicle* URoamCameraRig::GetVehicle() const
{
	return Cast<ARoamVehicle>(GetOwner());
}

void URoamCameraRig::SetCameraMode(ERoamCameraMode NewMode)
{
	if (NewMode == Mode || NewMode == ERoamCameraMode::Count)
	{
		return;
	}
	const ERoamCameraMode Old = Mode;
	Mode = NewMode;
	LookYaw = 0.0f;
	LookPitch = 0.0f;
	bNeedsSnap = true;
	OnModeChanged.Broadcast(Old, NewMode);
}

void URoamCameraRig::CycleCameraMode()
{
	ERoamCameraMode Next = ERoamCameraMode::Chase;
	switch (Mode)
	{
	case ERoamCameraMode::Chase:   Next = ERoamCameraMode::Hood; break;
	case ERoamCameraMode::Hood:    Next = ERoamCameraMode::Cockpit; break;
	case ERoamCameraMode::Cockpit: Next = ERoamCameraMode::Bumper; break;
	default:                       Next = ERoamCameraMode::Chase; break;
	}
	SetCameraMode(Next);
}

void URoamCameraRig::ApplyCarDefinition(const URoamCarDefinition* Definition)
{
	const FRoamCarGeometry Geometry = Definition ? Definition->Geometry : FRoamCarGeometry();
	HoodAnchor = Geometry.CameraHoodCm;
	CockpitAnchor = Geometry.CameraCockpitCm;
	BumperAnchor = Geometry.CameraBumperCm;
	ChaseDistanceCm = FMath::Max(450.0f, 1.45f * Geometry.LengthCm);
	ChaseHeightCm = FMath::Max(150.0f, 1.4f * Geometry.HeightCm);
	bNeedsSnap = true;
}

void URoamCameraRig::SnapToVehicle()
{
	bNeedsSnap = true;
}

void URoamCameraRig::AddLookInput(float YawDelta, float PitchDelta)
{
	LookYaw = FMath::UnwindDegrees(LookYaw + YawDelta);
	LookPitch = FMath::Clamp(LookPitch + PitchDelta, -60.0f, 60.0f);
}

void URoamCameraRig::AddImpactShake(float Strength)
{
	ShakeStrength = FMath::Clamp(ShakeStrength + Strength, 0.0f, 1.0f);
}

void URoamCameraRig::UpdateFromTelemetry(const FRoamVehicleTelemetry& Telemetry)
{
	SpeedKmh = Telemetry.SpeedKmh;
}

void URoamCameraRig::TickComponent(float DeltaTime, ELevelTick TickType, FActorComponentTickFunction* ThisTickFunction)
{
	Super::TickComponent(DeltaTime, TickType, ThisTickFunction);
	if (DeltaTime <= 0.0f || !GetVehicle())
	{
		return;
	}

	switch (Mode)
	{
	case ERoamCameraMode::Chase:
	case ERoamCameraMode::FreeLook:
		UpdateChase(DeltaTime);
		break;
	case ERoamCameraMode::Hood:
	case ERoamCameraMode::Cockpit:
	case ERoamCameraMode::Bumper:
		UpdateFixed(DeltaTime);
		break;
	case ERoamCameraMode::Photo:
	default:
		break; // the photo-mode system owns the camera transform
	}

	// Speed dependent field of view.
	const float SpeedAlpha = FMath::Clamp(SpeedKmh / FMath::Max(FovFullBoostKmh, 1.0f), 0.0f, 1.0f);
	const float TargetFov = (Mode == ERoamCameraMode::Chase || Mode == ERoamCameraMode::FreeLook)
		? ChaseBaseFov + FovSpeedBoost * FMath::Pow(SpeedAlpha, 1.5f)
		: InCarFov + 0.4f * FovSpeedBoost * SpeedAlpha;
	SetFieldOfView(FMath::FInterpTo(FieldOfView, TargetFov, DeltaTime, 3.0f));

	ShakeStrength = FMath::Max(0.0f, ShakeStrength - 2.5f * DeltaTime);
}

void URoamCameraRig::UpdateChase(float DeltaTime)
{
	const ARoamVehicle* Vehicle = GetVehicle();
	const FVector CarLocation = Vehicle->GetActorLocation();
	const float CarYaw = Vehicle->GetActorRotation().Yaw;

	if (bNeedsSnap)
	{
		SmoothedYaw = CarYaw;
		SmoothedLocation = CarLocation;
	}
	// Heading follow: smoothed car yaw so quick steering does not whip the camera around.
	const float YawError = FMath::FindDeltaAngleDegrees(SmoothedYaw, CarYaw);
	SmoothedYaw = FMath::UnwindDegrees(SmoothedYaw + YawError * (1.0f - FMath::Exp(-FollowRotationSpeed * DeltaTime)));
	// Chase mode: user look offset springs back; free look keeps it.
	if (Mode == ERoamCameraMode::Chase)
	{
		LookYaw = FMath::FInterpTo(LookYaw, 0.0f, DeltaTime, 2.5f);
		LookPitch = FMath::FInterpTo(LookPitch, 0.0f, DeltaTime, 2.5f);
	}

	const float SpeedAlpha = FMath::Clamp(SpeedKmh / FMath::Max(FovFullBoostKmh, 1.0f), 0.0f, 1.0f);
	const float Distance = ChaseDistanceCm + ChaseDistanceSpeedGainCm * SpeedAlpha;
	const FRotator OrbitRotation(LookPitch - 6.0f, SmoothedYaw + LookYaw, 0.0f);
	const FVector Pivot = CarLocation + FVector(0.0f, 0.0f, ChaseHeightCm * 0.55f);
	FVector Desired = Pivot - OrbitRotation.Vector() * Distance + FVector(0.0f, 0.0f, ChaseHeightCm * 0.45f);

	// Camera collision: pull in when the world is between the car and the camera.
	if (UWorld* World = GetWorld())
	{
		FHitResult Hit;
		FCollisionQueryParams Params(SCENE_QUERY_STAT(RoamCameraProbe), false, Vehicle);
		if (World->SweepSingleByChannel(Hit, Pivot, Desired, FQuat::Identity, RoamCollision::TraceCamera, FCollisionShape::MakeSphere(18.0f), Params))
		{
			Desired = Hit.Location;
		}
	}

	SmoothedLocation = bNeedsSnap ? Desired : FMath::VInterpTo(SmoothedLocation, Desired, DeltaTime, FollowLocationSpeed);
	const FVector LookTarget = CarLocation + FVector(0.0f, 0.0f, ChaseHeightCm * 0.35f) + OrbitRotation.Vector() * 250.0f;
	FRotator Rotation = (LookTarget - SmoothedLocation).Rotation();

	// Subtle shake: impacts plus a little speed buzz.
	const float Shake = ShakeStrength * 2.0f + 0.05f * SpeedAlpha * SpeedAlpha;
	if (Shake > KINDA_SMALL_NUMBER)
	{
		Rotation.Pitch += FMath::FRandRange(-1.0f, 1.0f) * Shake;
		Rotation.Yaw += FMath::FRandRange(-1.0f, 1.0f) * Shake;
		Rotation.Roll += FMath::FRandRange(-1.0f, 1.0f) * Shake * 0.5f;
	}

	SetWorldLocationAndRotation(SmoothedLocation, Rotation);
	bNeedsSnap = false;
}

void URoamCameraRig::UpdateFixed(float DeltaTime)
{
	const ARoamVehicle* Vehicle = GetVehicle();
	const FVector& Anchor = (Mode == ERoamCameraMode::Hood) ? HoodAnchor : (Mode == ERoamCameraMode::Cockpit ? CockpitAnchor : BumperAnchor);
	const FTransform CarTransform = Vehicle->GetActorTransform();
	LookYaw = FMath::FInterpTo(LookYaw, 0.0f, DeltaTime, 3.0f);
	LookPitch = FMath::FInterpTo(LookPitch, 0.0f, DeltaTime, 3.0f);

	FRotator Rotation = CarTransform.GetRotation().Rotator();
	Rotation.Yaw += FMath::Clamp(LookYaw, -120.0f, 120.0f);
	Rotation.Pitch += LookPitch;
	const float Shake = ShakeStrength * 2.0f;
	if (Shake > KINDA_SMALL_NUMBER)
	{
		Rotation.Pitch += FMath::FRandRange(-1.0f, 1.0f) * Shake;
		Rotation.Roll += FMath::FRandRange(-1.0f, 1.0f) * Shake;
	}
	SetWorldLocationAndRotation(CarTransform.TransformPosition(Anchor), Rotation);
	bNeedsSnap = false;
}
