// Copyright Epic Games, Inc. All Rights Reserved.

#pragma once

#include "CoreMinimal.h"
#include "GameFramework/HUD.h"
#include "RoamHUD.generated.h"

/**
 * HUD actor of Roamline. The real HUD is Slate and lives in URoamUISubsystem (created in OnHUDReady); this actor is the shell that
 * ties the Slate UI to the level's lifetime and, until the Slate HUD exists, draws a one-line canvas readout so that the placeholder
 * car, telemetry and notifications are visible in screenshots ("HUD shell alive").
 *
 * The readout is on while URoamSettings::bShowHudShellDebugText is true; the UI owner switches it off when the Slate HUD ships.
 */
UCLASS()
class SONNET55FORZA_API ARoamHUD : public AHUD
{
	GENERATED_BODY()

public:
	ARoamHUD();

	//~ Begin AActor / AHUD
	virtual void BeginPlay() override;
	virtual void EndPlay(const EEndPlayReason::Type EndPlayReason) override;
	virtual void DrawHUD() override;
	//~ End

private:
	void DrawLine(const FString& Text, float& InOutY, const FLinearColor& Color, float Scale = 1.0f);
};
