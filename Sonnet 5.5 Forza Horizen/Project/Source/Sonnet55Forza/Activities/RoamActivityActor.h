// Copyright Epic Games, Inc. All Rights Reserved.

#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "Activities/RoamActivitySubsystem.h"
#include "RoamActivityActor.generated.h"

/**
 * Visual prop of an activity (speed-trap gantry, zone banners, ramp, start arch, checkpoint beams ...). Placed by the editor world
 * builder from URoamWorldDefinition::Activities and linked by ActivityId. It carries NO logic: gates are evaluated by
 * URoamActivitySubsystem, so a streamed-out prop can never break an activity. It only mirrors the activity state for presentation
 * (flash on result, beam colour while armed, ...).
 *
 * ---- OWNER: activities agent ------------------------------------------------------------------------------------------------
 * Subclasses per type (speed trap, zone, drift, danger sign, race, trial, collectible) go in their own files under Activities/.
 */
UCLASS(Abstract)
class SONNET55FORZA_API ARoamActivityActor : public AActor
{
	GENERATED_BODY()

public:
	ARoamActivityActor();

	//~ Begin AActor
	virtual void BeginPlay() override;
	virtual void EndPlay(const EEndPlayReason::Type EndPlayReason) override;
	//~ End

	/** Id of the activity this prop belongs to. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Activity")
	FName ActivityId;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Activity")
	ERoamActivityType ActivityType = ERoamActivityType::SpeedTrap;

	/** Called when the subsystem state of this activity changes. OWNER: activities agent. */
	virtual void OnActivityStateChanged(ERoamActivityState NewState);

	/** Called with the result of this activity (flash, confetti, ...). OWNER: activities agent. */
	virtual void OnActivityResult(const FRoamActivityResult& Result);

private:
	void HandleStateChanged(FName Id, ERoamActivityState NewState);
	void HandleResult(const FRoamActivityResult& Result);

	FDelegateHandle StateHandle;
	FDelegateHandle ResultHandle;
};
