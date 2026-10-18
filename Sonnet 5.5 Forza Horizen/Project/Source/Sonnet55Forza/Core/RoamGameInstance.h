// Copyright Epic Games, Inc. All Rights Reserved.

#pragma once

#include "CoreMinimal.h"
#include "Engine/GameInstance.h"
#include "RoamGameInstance.generated.h"

class URoamCarCatalog;
class URoamRoadNetwork;
class URoamWorldDefinition;

/**
 * The game instance of Roamline (set in Config/DefaultEngine.ini GameInstanceClass). It lives for the whole session, owns the loaded
 * global data assets (car catalog, road network, world definition - referenced by URoamSettings) and hosts the game-instance
 * subsystems: URoamConsoleSubsystem, URoamSaveSubsystem, URoamUISubsystem.
 *
 * Data accessors load lazily and synchronously on first use and keep a strong reference, so callers can use the returned pointers
 * freely during the session. They return nullptr (and log once) if nothing is configured - the game runs without them.
 */
UCLASS()
class SONNET55FORZA_API URoamGameInstance : public UGameInstance
{
	GENERATED_BODY()

public:
	/** The Roam game instance of a world context, or nullptr (editor preview worlds, other game instance classes). */
	static URoamGameInstance* Get(const UObject* WorldContext);

	virtual void Init() override;

	URoamCarCatalog* GetCarCatalog();
	URoamRoadNetwork* GetRoadNetwork();
	URoamWorldDefinition* GetWorldDefinition();

	/** Drops the cached data and loads again from URoamSettings (after the settings or the assets changed). */
	void ReloadData();

private:
	UPROPERTY(Transient)
	TObjectPtr<URoamCarCatalog> CarCatalog;

	UPROPERTY(Transient)
	TObjectPtr<URoamRoadNetwork> RoadNetwork;

	UPROPERTY(Transient)
	TObjectPtr<URoamWorldDefinition> WorldDefinition;

	bool bCatalogTried = false;
	bool bRoadNetworkTried = false;
	bool bWorldDefinitionTried = false;
};
