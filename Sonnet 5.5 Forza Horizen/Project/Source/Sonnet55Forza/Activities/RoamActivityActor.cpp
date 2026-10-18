// Copyright Epic Games, Inc. All Rights Reserved.

#include "Activities/RoamActivityActor.h"

#include "Engine/World.h"

ARoamActivityActor::ARoamActivityActor()
{
	// Presentation only; the subsystem drives the logic.
	PrimaryActorTick.bCanEverTick = false;
	bReplicates = false;
}

void ARoamActivityActor::BeginPlay()
{
	Super::BeginPlay();
	if (URoamActivitySubsystem* Activities = GetWorld() ? GetWorld()->GetSubsystem<URoamActivitySubsystem>() : nullptr)
	{
		StateHandle = Activities->OnActivityStateChanged.AddUObject(this, &ARoamActivityActor::HandleStateChanged);
		ResultHandle = Activities->OnActivityResult.AddUObject(this, &ARoamActivityActor::HandleResult);
	}
}

void ARoamActivityActor::EndPlay(const EEndPlayReason::Type EndPlayReason)
{
	if (URoamActivitySubsystem* Activities = GetWorld() ? GetWorld()->GetSubsystem<URoamActivitySubsystem>() : nullptr)
	{
		Activities->OnActivityStateChanged.Remove(StateHandle);
		Activities->OnActivityResult.Remove(ResultHandle);
	}
	Super::EndPlay(EndPlayReason);
}

void ARoamActivityActor::HandleStateChanged(FName Id, ERoamActivityState NewState)
{
	if (Id == ActivityId)
	{
		OnActivityStateChanged(NewState);
	}
}

void ARoamActivityActor::HandleResult(const FRoamActivityResult& Result)
{
	if (Result.ActivityId == ActivityId)
	{
		OnActivityResult(Result);
	}
}

void ARoamActivityActor::OnActivityStateChanged(ERoamActivityState NewState)
{
	// OWNER: activities agent.
	(void)NewState;
}

void ARoamActivityActor::OnActivityResult(const FRoamActivityResult& Result)
{
	// OWNER: activities agent.
	(void)Result;
}
