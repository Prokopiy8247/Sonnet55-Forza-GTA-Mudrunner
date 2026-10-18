// Copyright Epic Games, Inc. All Rights Reserved.

#include "RoamEditorLibrary.h"

#include "Core/RoamLog.h"
#include "Core/RoamSettings.h"
#include "Core/RoamTypes.h"
#include "Engine/World.h"
#include "GameFramework/GameModeBase.h"
#include "GameFramework/WorldSettings.h"
#include "Misc/EngineVersion.h"
#include "PhysicalMaterials/PhysicalMaterial.h"
#include "Components/PrimitiveComponent.h"

FString URoamEditorLibrary::GetRoamEditorLibraryStatus()
{
	return FString::Printf(TEXT("RoamEditorLibrary OK (UE %s)"), *FEngineVersion::Current().ToString(EVersionComponent::Patch));
}

int32 URoamEditorLibrary::SmokeAdd(int32 A, int32 B)
{
	return A + B;
}

bool URoamEditorLibrary::SetWorldGameModeOverride(UWorld* World, TSubclassOf<AGameModeBase> GameModeClass)
{
	if (!World || !GameModeClass)
	{
		return false;
	}
	AWorldSettings* Settings = World->GetWorldSettings();
	if (!Settings)
	{
		return false;
	}
	Settings->Modify();
	Settings->DefaultGameMode = GameModeClass;
	return true;
}

bool URoamEditorLibrary::SetComponentPhysicalMaterial(UPrimitiveComponent* Component, UPhysicalMaterial* PhysicalMaterial)
{
	if (!Component)
	{
		return false;
	}
	Component->Modify();
	Component->BodyInstance.SetPhysMaterialOverride(PhysicalMaterial);
	return true;
}

bool URoamEditorLibrary::ConfigureRoamPhysicalMaterial(UPhysicalMaterial* PhysicalMaterial, int32 RoamSurfaceIndex, float Friction, float StaticFriction, float Density)
{
	if (!PhysicalMaterial)
	{
		return false;
	}
	PhysicalMaterial->Modify();
	PhysicalMaterial->SurfaceType = Roam::PhysicalSurfaceFromSurface(static_cast<ERoamSurface>(FMath::Clamp(RoamSurfaceIndex, 0, static_cast<int32>(ERoamSurface::Count) - 1)));
	PhysicalMaterial->Friction = Friction;
	PhysicalMaterial->StaticFriction = StaticFriction;
	PhysicalMaterial->Density = Density;
	PhysicalMaterial->MarkPackageDirty();
	return true;
}

FString URoamEditorLibrary::DescribeRoamSettings()
{
	const URoamSettings* Settings = GetDefault<URoamSettings>();
	const FString Summary = Settings
		? FString::Printf(TEXT("RoamSettings: catalog=%s road=%s world=%s vehicle=%s"),
			*Settings->CarCatalog.ToString(), *Settings->RoadNetwork.ToString(), *Settings->WorldDefinition.ToString(), *Settings->DefaultVehicleClass.ToString())
		: FString(TEXT("RoamSettings: <none>"));
	UE_LOG(LogRoam, Display, TEXT("%s"), *Summary);
	return Summary;
}
