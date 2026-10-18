// Copyright Epic Games, Inc. All Rights Reserved.

#include "Activities/RoamActivityMarkerActor.h"

#include "Activities/RoamActivityLogic.h"
#include "Components/InstancedStaticMeshComponent.h"
#include "Components/SceneComponent.h"
#include "Engine/StaticMesh.h"
#include "Materials/MaterialInstanceDynamic.h"
#include "Materials/MaterialInterface.h"
#include "UObject/ConstructorHelpers.h"

namespace
{
	UInstancedStaticMeshComponent* MakeInstances(ARoamActivityMarkerActor* Owner, USceneComponent* Root, const TCHAR* Name, UStaticMesh* Mesh)
	{
		UInstancedStaticMeshComponent* Component = Owner->CreateDefaultSubobject<UInstancedStaticMeshComponent>(Name);
		Component->SetupAttachment(Root);
		Component->SetStaticMesh(Mesh);
		Component->SetCollisionEnabled(ECollisionEnabled::NoCollision);
		Component->SetCanEverAffectNavigation(false);
		Component->SetCastShadow(false);
		Component->bCastDynamicShadow = false;
		Component->SetMobility(EComponentMobility::Movable);
		return Component;
	}
}

ARoamActivityMarkerActor::ARoamActivityMarkerActor()
{
	USceneComponent* Root = CreateDefaultSubobject<USceneComponent>(TEXT("Root"));
	SetRootComponent(Root);

	static ConstructorHelpers::FObjectFinder<UStaticMesh> CylinderFinder(TEXT("/Engine/BasicShapes/Cylinder.Cylinder"));
	static ConstructorHelpers::FObjectFinder<UStaticMesh> CubeFinder(TEXT("/Engine/BasicShapes/Cube.Cube"));
	static ConstructorHelpers::FObjectFinder<UMaterialInterface> MaterialFinder(TEXT("/Engine/BasicShapes/BasicShapeMaterial.BasicShapeMaterial"));

	PostInstances = MakeInstances(this, Root, TEXT("Posts"), CylinderFinder.Object);
	PlateInstances = MakeInstances(this, Root, TEXT("Plates"), CubeFinder.Object);
	BaseMaterial = MaterialFinder.Object;
}

int32 ARoamActivityMarkerActor::GetNumInstances() const
{
	return (PostInstances ? PostInstances->GetInstanceCount() : 0) + (PlateInstances ? PlateInstances->GetInstanceCount() : 0);
}

void ARoamActivityMarkerActor::SetTint(const FLinearColor& Color)
{
	if (TintMaterial)
	{
		TintMaterial->SetVectorParameterValue(TEXT("Color"), Color);
	}
}

void ARoamActivityMarkerActor::BuildFromDefinition(const FRoamActivityDef& Definition)
{
	ActivityId = Definition.ActivityId;
	ActivityType = Definition.Type;
	Tint = RoamActivity::TypeColor(Definition.Type);

	PostInstances->ClearInstances();
	PlateInstances->ClearInstances();
	if (Definition.Gates.Num() == 0)
	{
		return;
	}
	SetActorLocation(Definition.Gates[0].Center);

	if (BaseMaterial)
	{
		TintMaterial = UMaterialInstanceDynamic::Create(BaseMaterial, this);
		PostInstances->SetMaterial(0, TintMaterial);
		PlateInstances->SetMaterial(0, TintMaterial);
		SetTint(Tint);
	}

	if (Definition.Type == ERoamActivityType::Collectible || Definition.Type == ERoamActivityType::PhotoSpot)
	{
		AddBeacon(Definition.Gates[0]);
		return;
	}
	const int32 Last = Definition.Gates.Num() - 1;
	const bool bChain = Definition.Type == ERoamActivityType::CheckpointRace || Definition.Type == ERoamActivityType::TimeTrial;
	for (int32 i = 0; i <= Last; ++i)
	{
		const bool bEnd = (i == 0 || i == Last);
		AddGantry(Definition.Gates[i], (bChain && !bEnd) ? 0.6f : 1.0f, bEnd);
	}
}

void ARoamActivityMarkerActor::AddGantry(const FRoamGate& Gate, float Scale, bool bBigBanner)
{
	const FVector Forward = Gate.Forward.GetSafeNormal();
	FVector Right = FVector::CrossProduct(FVector::UpVector, Forward).GetSafeNormal();
	if (Right.IsNearlyZero())
	{
		Right = FVector::RightVector;
	}
	const FQuat Rotation = FRotationMatrix::MakeFromXZ(Forward, FVector::UpVector).ToQuat();
	const FVector Origin = GetActorLocation();
	const float PostHeight = 700.0f * Scale;
	const float GroundOffset = -150.0f; // gate centres sit 150 cm above the road surface

	// Gantry posts (engine cylinder is 100 x 100 cm).
	for (const float Side : { -1.0f, 1.0f })
	{
		const FVector Center = Gate.Center + Right * (Side * Gate.HalfWidthCm) + FVector(0.0, 0.0, GroundOffset + PostHeight * 0.5f);
		PostInstances->AddInstance(FTransform(Rotation, Center - Origin, FVector(0.45f * Scale, 0.45f * Scale, PostHeight / 100.0f)));
	}
	// Beam across the road (engine cube is 100 cm).
	const FVector BeamCenter = Gate.Center + FVector(0.0, 0.0, GroundOffset + PostHeight);
	PlateInstances->AddInstance(FTransform(Rotation, BeamCenter - Origin, FVector(0.6f * Scale, (2.0f * Gate.HalfWidthCm) / 100.0f + 0.5f, 0.7f * Scale)));
	// Banner plate hanging under the beam (thin in X, wide in Y).
	const float BannerWidth = Gate.HalfWidthCm * (bBigBanner ? 1.2f : 0.7f) / 100.0f;
	const float BannerHeight = (bBigBanner ? 2.2f : 1.0f) * Scale;
	PlateInstances->AddInstance(FTransform(Rotation, BeamCenter - Origin - FVector(0.0, 0.0, 60.0f * Scale + BannerHeight * 50.0f), FVector(0.12f, BannerWidth, BannerHeight)));
}

void ARoamActivityMarkerActor::AddBeacon(const FRoamGate& Gate)
{
	const FVector Origin = GetActorLocation();
	PostInstances->AddInstance(FTransform(FQuat::Identity, Gate.Center - Origin + FVector(0.0, 0.0, 600.0), FVector(0.35f, 0.35f, 12.0f)));
	const FQuat Tilt = FRotator(45.0f, 45.0f, 0.0f).Quaternion();
	PlateInstances->AddInstance(FTransform(Tilt, Gate.Center - Origin + FVector(0.0, 0.0, 1300.0), FVector(1.4f, 1.4f, 1.4f)));
}

void ARoamActivityMarkerActor::OnActivityStateChanged(ERoamActivityState NewState)
{
	switch (NewState)
	{
	case ERoamActivityState::Armed:
	case ERoamActivityState::Active:
		SetTint(FLinearColor(FMath::Min(Tint.R * 1.6f + 0.2f, 1.0f), FMath::Min(Tint.G * 1.6f + 0.2f, 1.0f), FMath::Min(Tint.B * 1.6f + 0.2f, 1.0f), 1.0f));
		break;
	case ERoamActivityState::Result:
		SetTint(FLinearColor::White);
		break;
	default:
		SetTint(Tint);
		break;
	}
}

void ARoamActivityMarkerActor::OnActivityResult(const FRoamActivityResult& Result)
{
	if (Result.bCompleted && Result.Stars >= 3)
	{
		SetTint(FLinearColor(1.0f, 0.85f, 0.2f, 1.0f)); // gold when 3-starred
	}
}
