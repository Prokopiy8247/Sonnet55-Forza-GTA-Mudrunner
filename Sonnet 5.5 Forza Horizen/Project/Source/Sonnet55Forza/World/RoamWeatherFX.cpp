// Copyright Epic Games, Inc. All Rights Reserved.

#include "World/RoamWeatherFX.h"

#include "Core/RoamLog.h"
#include "Engine/StaticMesh.h"
#include "Materials/MaterialInstanceDynamic.h"
#include "Materials/MaterialInterface.h"
#include "Math/RandomStream.h"
#include "UObject/ConstructorHelpers.h"

namespace
{
	/** Optional project material (future art pass); engine fallback below. Parameter "Color": rgb = emissive, a = opacity. */
	const TCHAR* const GProjectRainMaterial = TEXT("/Game/Forza/Materials/M_Roam_Rain_Streak.M_Roam_Rain_Streak");
	const TCHAR* const GEngineRainMaterial = TEXT("/Engine/EngineDebugMaterials/M_SimpleUnlitTranslucent.M_SimpleUnlitTranslucent");

	FORCEINLINE double WrapTo(double X, double Length)
	{
		return X - Length * FMath::FloorToDouble(X / Length);
	}
}

URoamRainFXComponent::URoamRainFXComponent(const FObjectInitializer& ObjectInitializer)
	: Super(ObjectInitializer)
{
	PrimaryComponentTick.bCanEverTick = false;
	SetMobility(EComponentMobility::Movable);
	SetCollisionEnabled(ECollisionEnabled::NoCollision);
	SetGenerateOverlapEvents(false);
	SetCanEverAffectNavigation(false);
	SetCastShadow(false);
	bCastDynamicShadow = false;
	bAffectDynamicIndirectLighting = false;
	bAffectDistanceFieldLighting = false;
	bReceivesDecals = false;
	bUseAsOccluder = false;
	bNeverDistanceCull = true;
	bVisibleInRayTracing = false;
	bVisibleInReflectionCaptures = false;
	bVisibleInRealTimeSkyCaptures = false;

	static ConstructorHelpers::FObjectFinder<UStaticMesh> PlaneMesh(TEXT("/Engine/BasicShapes/Plane.Plane"));
	if (PlaneMesh.Succeeded())
	{
		SetStaticMesh(PlaneMesh.Object);
	}
}

bool URoamRainFXComponent::InitFX()
{
	if (bReady)
	{
		return true;
	}
	if (!GetStaticMesh() || PoolSize <= 0)
	{
		UE_LOG(LogRoamWorld, Warning, TEXT("RainFX: no plane mesh - rain disabled"));
		return false;
	}

	UMaterialInterface* Base = LoadObject<UMaterialInterface>(nullptr, GProjectRainMaterial, nullptr, LOAD_NoWarn | LOAD_Quiet);
	if (!Base)
	{
		Base = LoadObject<UMaterialInterface>(nullptr, GEngineRainMaterial, nullptr, LOAD_NoWarn | LOAD_Quiet);
	}
	if (!Base)
	{
		UE_LOG(LogRoamWorld, Warning, TEXT("RainFX: no streak material found - rain disabled"));
		return false;
	}
	StreakMID = UMaterialInstanceDynamic::Create(Base, this);
	SetMaterial(0, StreakMID);

	// Deterministic pool (same rain every run, handy for screenshots).
	FRandomStream Rand(0x524F414D);
	Seeds.SetNumUninitialized(PoolSize);
	SpeedMuls.SetNumUninitialized(PoolSize);
	for (int32 i = 0; i < PoolSize; ++i)
	{
		Seeds[i] = FVector3f(Rand.FRand(), Rand.FRand(), Rand.FRand());
		SpeedMuls[i] = 0.85f + 0.3f * Rand.FRand();
	}

	TArray<FTransform> Initial;
	Initial.Init(FTransform(FQuat::Identity, FVector::ZeroVector, FVector(0.0001)), PoolSize);
	AddInstances(Initial, /*bShouldReturnIndices*/ false, /*bWorldSpace*/ false, /*bUpdateNavigation*/ false);
	Scratch.Reserve(PoolSize);
	SetVisibility(false);
	bReady = true;
	return true;
}

void URoamRainFXComponent::ApplyMaterialColor(float Intensity01, float ExposureEV100, float Daylight01)
{
	if (!StreakMID)
	{
		return;
	}
	// Quantised key: only touch the MID when something visible changed.
	const float Key = FMath::RoundToFloat(ExposureEV100 * 20.0f) * 1000.0f + FMath::RoundToFloat(Daylight01 * 50.0f) * 10.0f + FMath::RoundToFloat(Intensity01 * 8.0f);
	if (FMath::IsNearlyEqual(Key, LastColorKey))
	{
		return;
	}
	LastColorKey = Key;

	const float ExposureScale = 1.2f * FMath::Exp2(ExposureEV100);
	// Streak "pixel" brightness: bright and bluish-white by day, almost invisible at night (headlights are not modelled here).
	const float Brightness = FMath::Lerp(0.10f, 0.80f, Daylight01);
	const FLinearColor Tint(0.80f, 0.86f, 0.96f);
	const float Alpha = FMath::Lerp(0.22f, 0.50f, FMath::Clamp(Intensity01, 0.0f, 1.0f));
	StreakMID->SetVectorParameterValue(TEXT("Color"), FLinearColor(Tint.R * Brightness * ExposureScale, Tint.G * Brightness * ExposureScale, Tint.B * Brightness * ExposureScale, Alpha));
}

void URoamRainFXComponent::UpdateRain(float Intensity01, const FVector& CameraLocation, const FVector& CameraVelocity, const FVector& WindCmPerSec,
	float ExposureEV100, float Daylight01, float FallSpeed, float DeltaSeconds)
{
	if (!bReady)
	{
		return;
	}
	if (Intensity01 < 0.02f)
	{
		if (IsVisible())
		{
			SetVisibility(false);
		}
		ActiveCount = 0;
		return;
	}
	if (!IsVisible())
	{
		SetVisibility(true);
	}

	Clock += FMath::Min(DeltaSeconds, 0.1f);
	SetWorldLocation(CameraLocation);
	ApplyMaterialColor(Intensity01, ExposureEV100, Daylight01);

	const int32 Active = FMath::Clamp(FMath::CeilToInt(PoolSize * FMath::Clamp(Intensity01, 0.0f, 1.0f)), 0, PoolSize);
	const int32 Count = FMath::Max(Active, WrittenCount);
	ActiveCount = Active;

	const float Hxy = BoxHalfExtentXY;
	const float Lxy = 2.0f * Hxy;
	const float H = BoxHeight;
	const float ZBelow = 0.35f * H;
	const FVector Box(Lxy, Lxy, H);

	Scratch.SetNum(Count, EAllowShrinking::No);
	for (int32 i = 0; i < Count; ++i)
	{
		if (i >= Active)
		{
			Scratch[i] = FTransform(FQuat::Identity, FVector::ZeroVector, FVector(0.0001));
			continue;
		}

		const FVector3f& S = Seeds[i];
		const float SpeedMul = SpeedMuls[i];
		const FVector DropVel(WindCmPerSec.X * 0.7, WindCmPerSec.Y * 0.7, -FallSpeed * SpeedMul);

		// Position of the drop relative to the camera, wrapped into the box (pure function of time and camera position).
		const FVector P = FVector(S.X * Box.X, S.Y * Box.Y, S.Z * Box.Z) + DropVel * Clock - CameraLocation;
		const FVector Rel(
			WrapTo(P.X + Hxy, Lxy) - Hxy,
			WrapTo(P.Y + Hxy, Lxy) - Hxy,
			WrapTo(P.Z + ZBelow, H) - ZBelow);

		const float Dist = static_cast<float>(Rel.Size());
		if (Dist < 30.0f)
		{
			Scratch[i] = FTransform(FQuat::Identity, FVector::ZeroVector, FVector(0.0001));
			continue;
		}

		const FVector Vrel = DropVel - CameraVelocity;
		const float Speed = static_cast<float>(Vrel.Size());
		const FVector L = Speed > 1.0f ? Vrel / Speed : FVector(0.0, 0.0, -1.0);
		const FVector ToCam = -Rel / Dist;
		FVector X = FVector::CrossProduct(L, ToCam);
		if (X.SizeSquared() < 1.0e-6)
		{
			X = FVector::CrossProduct(L, FVector::XAxisVector);
		}
		X.Normalize();

		// Fade towards the box edge (no popping) and keep far streaks visible by widening them with distance.
		const float EdgeT = FMath::Max(FMath::Abs(static_cast<float>(Rel.X)), FMath::Abs(static_cast<float>(Rel.Y))) / Hxy;
		const float Fade = (1.0f - FMath::SmoothStep(0.70f, 1.0f, EdgeT)) * FMath::SmoothStep(60.0f, 320.0f, Dist);
		const float Length = FMath::Clamp(Speed * ShutterSeconds, MinStreakLength, MaxStreakLength) * (0.8f + 0.4f * S.Z) * Fade;
		const float Width = (0.9f + Dist * 0.0016f) * Fade;

		const FQuat Q = FRotationMatrix::MakeFromXY(X, L).ToQuat();
		Scratch[i] = FTransform(Q, Rel, FVector(Width * 0.01f, Length * 0.01f, 1.0f));
	}

	BatchUpdateInstancesTransforms(0, Scratch, /*bWorldSpace*/ false, /*bMarkRenderStateDirty*/ true, /*bTeleport*/ true);
	WrittenCount = Active;
}
