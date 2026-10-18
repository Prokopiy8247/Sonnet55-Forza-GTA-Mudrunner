// Copyright Epic Games, Inc. All Rights Reserved.

#include "World/RoamRegionSubsystem.h"

#include "Activities/RoamActivitySubsystem.h"
#include "Console/RoamConsoleSubsystem.h"
#include "Core/RoamCollision.h"
#include "Core/RoamGameInstance.h"
#include "Core/RoamLog.h"
#include "Data/RoamWorldDefinition.h"
#include "Engine/Engine.h"
#include "Engine/World.h"
#include "UI/RoamUISubsystem.h"
#include "Vehicle/RoamVehicle.h"

URoamRegionSubsystem* URoamRegionSubsystem::Get(const UObject* WorldContext)
{
	const UWorld* World = GEngine ? GEngine->GetWorldFromContextObject(WorldContext, EGetWorldErrorMode::ReturnNull) : nullptr;
	return World ? World->GetSubsystem<URoamRegionSubsystem>() : nullptr;
}

bool URoamRegionSubsystem::DoesSupportWorldType(const EWorldType::Type WorldType) const
{
	return WorldType == EWorldType::Game || WorldType == EWorldType::PIE;
}

void URoamRegionSubsystem::Initialize(FSubsystemCollectionBase& Collection)
{
	Super::Initialize(Collection);
}

URoamWorldDefinition* URoamRegionSubsystem::GetWorldDefinition() const
{
	URoamGameInstance* GameInstance = URoamGameInstance::Get(this);
	return GameInstance ? GameInstance->GetWorldDefinition() : nullptr;
}

const FRoamRegionDef* URoamRegionSubsystem::GetCurrentRegion() const
{
	const URoamWorldDefinition* Definition = GetWorldDefinition();
	return (Definition && !CurrentRegionId.IsNone()) ? Definition->FindRegion(CurrentRegionId) : nullptr;
}

FName URoamRegionSubsystem::GetRegionIdAt(FVector WorldLocation) const
{
	const URoamWorldDefinition* Definition = GetWorldDefinition();
	const FRoamRegionDef* Region = Definition ? Definition->FindRegionAt(WorldLocation) : nullptr;
	return Region ? Region->RegionId : NAME_None;
}

FName URoamRegionSubsystem::GetCurrentClimateZone() const
{
	const FRoamRegionDef* Region = GetCurrentRegion();
	return Region ? Region->ClimateZone : NAME_None;
}

float URoamRegionSubsystem::GetTrafficDensityScaleAt(FVector WorldLocation) const
{
	const URoamWorldDefinition* Definition = GetWorldDefinition();
	const FRoamRegionDef* Region = Definition ? Definition->FindRegionAt(WorldLocation) : nullptr;
	return Region ? Region->TrafficDensityScale : 1.0f;
}

void URoamRegionSubsystem::Tick(float DeltaTime)
{
	Super::Tick(DeltaTime);
	PollAccumulator += DeltaTime;
	if (PollAccumulator < 0.25f)
	{
		return;
	}
	PollAccumulator = 0.0f;

	const URoamWorldDefinition* Definition = GetWorldDefinition();
	const ARoamVehicle* Vehicle = ARoamVehicle::GetPlayerVehicle(this);
	if (!Definition || !Vehicle)
	{
		return;
	}
	const FVector Location = Vehicle->GetActorLocation();
	const FRoamRegionDef* Found = Definition->FindRegionAt(Location);
	const FName FoundId = Found ? Found->RegionId : NAME_None;
	if (FoundId == CurrentRegionId)
	{
		return;
	}

	// Hysteresis: stay in the old region until we are clearly outside its rectangle.
	if (const FRoamRegionDef* Old = GetCurrentRegion())
	{
		const double OutsideX = FMath::Max(Old->MinXY.X - Location.X, Location.X - Old->MaxXY.X);
		const double OutsideY = FMath::Max(Old->MinXY.Y - Location.Y, Location.Y - Old->MaxXY.Y);
		if (FMath::Max(OutsideX, OutsideY) < RegionHysteresisCm && !FoundId.IsNone() && Old->Priority >= (Found ? Found->Priority : 0))
		{
			return;
		}
	}
	SetCurrentRegion(FoundId, true);
}

void URoamRegionSubsystem::SetCurrentRegion(FName NewRegionId, bool bPopup)
{
	const FName Old = CurrentRegionId;
	CurrentRegionId = NewRegionId;
	UE_LOG(LogRoamWorld, Display, TEXT("ROAM_REGION %s -> %s"), *Old.ToString(), *NewRegionId.ToString());
	OnRegionChanged.Broadcast(Old, NewRegionId);

	if (bPopup && !NewRegionId.IsNone() && GetWorld())
	{
		const double Now = GetWorld()->GetTimeSeconds();
		const double* Last = LastPopupByRegion.Find(NewRegionId);
		if (!Last || Now - *Last >= RegionPopupCooldownSec)
		{
			ForceRegionPopup();
		}
	}
}

void URoamRegionSubsystem::ForceRegionPopup()
{
	const FRoamRegionDef* Region = GetCurrentRegion();
	URoamUISubsystem* UI = URoamUISubsystem::Get(this);
	if (!Region || !UI || !GetWorld())
	{
		return;
	}
	LastPopupByRegion.Add(Region->RegionId, GetWorld()->GetTimeSeconds());
	UI->ShowRegionName(Region->DisplayName, Region->Subtitle);
}

bool URoamRegionSubsystem::ResolveTeleportTransform(const FString& Text, FTransform& OutTransform, FString& OutLabel, FString* OutError) const
{
	const URoamWorldDefinition* Definition = GetWorldDefinition();
	if (!Definition)
	{
		if (OutError) { *OutError = TEXT("no world definition is configured (URoamSettings::WorldDefinition)"); }
		return false;
	}
	FVector Location = FVector::ZeroVector;
	float YawDeg = 0.0f;
	if (!Definition->ResolveTeleportTarget(Text, Location, YawDeg, &OutLabel, OutError))
	{
		return false;
	}
	// Drop onto the ground: trace from far above with the wheel channel.
	if (UWorld* World = GetWorld())
	{
		FHitResult Hit;
		const FVector Start(Location.X, Location.Y, Location.Z > 0.0 ? Location.Z + 20000.0 : 120000.0);
		const FVector End(Location.X, Location.Y, -50000.0);
		if (World->LineTraceSingleByChannel(Hit, Start, End, RoamCollision::TraceWheel))
		{
			Location.Z = Hit.ImpactPoint.Z + 60.0;
		}
		else if (Location.Z <= 0.0)
		{
			Location.Z = 20000.0; // unknown ground (streaming): start high and let the car fall
		}
	}
	OutTransform = FTransform(FRotator(0.0f, YawDeg, 0.0f), Location);
	return true;
}

ROAM_REGISTER_CONSOLE_COMMAND_CATEGORY("tp", "tp <region|poi>", "Teleport the car to a region centre or point of interest.", "world",
	[](const FRoamConsoleContext& Ctx) -> FString
	{
		URoamRegionSubsystem* Regions = Ctx.World ? Ctx.World->GetSubsystem<URoamRegionSubsystem>() : nullptr;
		ARoamVehicle* Vehicle = ARoamVehicle::GetPlayerVehicle(Ctx.World);
		if (!Regions || !Vehicle)
		{
			return Ctx.Fail(TEXT("no player vehicle / region system"));
		}
		if (Ctx.NumArgs() == 0)
		{
			return Ctx.Fail(TEXT("usage: tp <region|poi>   (see 'regions')"));
		}
		FTransform Target;
		FString Label;
		FString Error;
		if (!Regions->ResolveTeleportTransform(Ctx.JoinFrom(0), Target, Label, &Error))
		{
			// Activity ids ("trap_03", "tt_loop") resolve too; plain numbers stay reserved for act.tp.
			URoamActivitySubsystem* Activities = Ctx.World->GetSubsystem<URoamActivitySubsystem>();
			FString ActivityError;
			if (Ctx.JoinFrom(0).IsNumeric() || !Activities || !Activities->ResolveActivityTeleport(Ctx.JoinFrom(0), Target, Label, &ActivityError))
			{
				return Ctx.Fail(Error);
			}
		}
		Vehicle->TeleportVehicle(Target, false);
		return FString::Printf(TEXT("teleported to %s (%.0f, %.0f, %.0f)"), *Label, Target.GetLocation().X, Target.GetLocation().Y, Target.GetLocation().Z);
	});

ROAM_REGISTER_CONSOLE_COMMAND_CATEGORY("regions", "regions", "List regions and teleport targets.", "world",
	[](const FRoamConsoleContext& Ctx) -> FString
	{
		URoamGameInstance* GameInstance = Cast<URoamGameInstance>(Ctx.GameInstance);
		const URoamWorldDefinition* Definition = GameInstance ? GameInstance->GetWorldDefinition() : nullptr;
		if (!Definition)
		{
			return Ctx.Fail(TEXT("no world definition is configured"));
		}
		FString Text = FString::Printf(TEXT("%d regions, %d points of interest"), Definition->Regions.Num(), Definition->Pois.Num());
		for (const FRoamRegionDef& Region : Definition->Regions)
		{
			Text += FString::Printf(TEXT("\n  region %-16s %s"), *Region.RegionId.ToString(), *Region.DisplayName.ToString());
		}
		for (const FRoamPoiDef& Poi : Definition->Pois)
		{
			if (Poi.bTeleportTarget)
			{
				Text += FString::Printf(TEXT("\n  poi    %-16s %s"), *Poi.PoiId.ToString(), *Poi.DisplayName.ToString());
			}
		}
		return Text;
	});
