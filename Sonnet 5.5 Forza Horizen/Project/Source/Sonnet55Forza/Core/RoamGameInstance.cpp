// Copyright Epic Games, Inc. All Rights Reserved.

#include "Core/RoamGameInstance.h"

#include "Console/RoamConsoleSubsystem.h"
#include "Core/RoamLog.h"
#include "Core/RoamSettings.h"
#include "Data/RoamCarCatalog.h"
#include "Data/RoamRoadNetwork.h"
#include "Data/RoamWorldDefinition.h"
#include "Engine/Engine.h"
#include "Engine/World.h"
#include "Save/RoamSaveSubsystem.h"

URoamGameInstance* URoamGameInstance::Get(const UObject* WorldContext)
{
	const UWorld* World = GEngine ? GEngine->GetWorldFromContextObject(WorldContext, EGetWorldErrorMode::ReturnNull) : nullptr;
	return World ? Cast<URoamGameInstance>(World->GetGameInstance()) : nullptr;
}

void URoamGameInstance::Init()
{
	Super::Init();
	UE_LOG(LogRoam, Display, TEXT("ROAM_GAME_INSTANCE_INIT (Roamline: Open Roads)"));
}

void URoamGameInstance::ReloadData()
{
	CarCatalog = nullptr;
	RoadNetwork = nullptr;
	WorldDefinition = nullptr;
	bCatalogTried = bRoadNetworkTried = bWorldDefinitionTried = false;
}

namespace
{
	template <typename TAsset>
	TAsset* LoadConfigured(const TSoftObjectPtr<TAsset>& Soft, bool& bTried, const TCHAR* What)
	{
		if (Soft.IsNull())
		{
			if (!bTried)
			{
				UE_LOG(LogRoam, Log, TEXT("%s: not configured in Project Settings > Roamline (running without it)"), What);
			}
			bTried = true;
			return nullptr;
		}
		TAsset* Loaded = Soft.LoadSynchronous();
		if (!Loaded && !bTried)
		{
			UE_LOG(LogRoam, Log, TEXT("%s: %s does not exist or failed to load (running without it)"), What, *Soft.ToString());
		}
		bTried = true;
		return Loaded;
	}
}

URoamCarCatalog* URoamGameInstance::GetCarCatalog()
{
	if (!CarCatalog && !bCatalogTried)
	{
		CarCatalog = LoadConfigured(GetDefault<URoamSettings>()->CarCatalog, bCatalogTried, TEXT("Car catalog"));
	}
	return CarCatalog;
}

URoamRoadNetwork* URoamGameInstance::GetRoadNetwork()
{
	if (!RoadNetwork && !bRoadNetworkTried)
	{
		RoadNetwork = LoadConfigured(GetDefault<URoamSettings>()->RoadNetwork, bRoadNetworkTried, TEXT("Road network"));
	}
	return RoadNetwork;
}

URoamWorldDefinition* URoamGameInstance::GetWorldDefinition()
{
	if (!WorldDefinition && !bWorldDefinitionTried)
	{
		WorldDefinition = LoadConfigured(GetDefault<URoamSettings>()->WorldDefinition, bWorldDefinitionTried, TEXT("World definition"));
	}
	return WorldDefinition;
}
