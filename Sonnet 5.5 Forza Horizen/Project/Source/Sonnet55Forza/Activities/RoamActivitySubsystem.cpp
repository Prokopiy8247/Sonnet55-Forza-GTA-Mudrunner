// Copyright Epic Games, Inc. All Rights Reserved.

#include "Activities/RoamActivitySubsystem.h"

#include "Activities/RoamActivityLogic.h"
#include "Activities/RoamActivityMarkerActor.h"
#include "Console/RoamConsoleSubsystem.h"
#include "Core/RoamCollision.h"
#include "Core/RoamGameInstance.h"
#include "Core/RoamLog.h"
#include "Data/RoamRoadNetwork.h"
#include "Engine/Engine.h"
#include "Engine/GameInstance.h"
#include "Engine/World.h"
#include "EngineUtils.h"
#include "Save/RoamSaveSubsystem.h"
#include "UI/RoamUISubsystem.h"
#include "Vehicle/RoamVehicle.h"

namespace
{
	/** Position jumps larger than this between two samples are teleports (150 m). */
	constexpr double MaxSegmentCm = 15000.0;

	URoamSaveSubsystem* GetSave(const UWorld* World)
	{
		return World && World->GetGameInstance() ? World->GetGameInstance()->GetSubsystem<URoamSaveSubsystem>() : nullptr;
	}

	float GetParam(const FRoamActivityDef& Def, const TCHAR* Name, float Default)
	{
		const float* Value = Def.Params.Find(FName(Name));
		return Value ? *Value : Default;
	}

	FVector Flat(const FVector& V)
	{
		const FVector F(V.X, V.Y, 0.0);
		return F.IsNearlyZero() ? FVector::ZeroVector : F.GetSafeNormal();
	}
}

URoamActivitySubsystem* URoamActivitySubsystem::Get(const UObject* WorldContext)
{
	const UWorld* World = GEngine ? GEngine->GetWorldFromContextObject(WorldContext, EGetWorldErrorMode::ReturnNull) : nullptr;
	return World ? World->GetSubsystem<URoamActivitySubsystem>() : nullptr;
}

bool URoamActivitySubsystem::DoesSupportWorldType(const EWorldType::Type WorldType) const
{
	return WorldType == EWorldType::Game || WorldType == EWorldType::PIE;
}

void URoamActivitySubsystem::Initialize(FSubsystemCollectionBase& Collection)
{
	Super::Initialize(Collection);
}

void URoamActivitySubsystem::Deinitialize()
{
	UnbindVehicle();
	Activities.Reset();
	Runtime.Reset();
	Markers.Reset();
	Super::Deinitialize();
}

void URoamActivitySubsystem::OnWorldBeginPlay(UWorld& InWorld)
{
	Super::OnWorldBeginPlay(InWorld);
	bBegunPlay = true;
	ReloadFromWorldDefinition();
	if (Activities.Num() == 0)
	{
		if (URoamGameInstance* GameInstance = URoamGameInstance::Get(this))
		{
			if (URoamRoadNetwork* Network = GameInstance->GetRoadNetwork())
			{
				GenerateDefaultActivities(Network);
			}
		}
	}
	SpawnMarkers();
}

void URoamActivitySubsystem::ReloadFromWorldDefinition()
{
	Activities.Reset();
	Runtime.Reset();
	if (URoamGameInstance* GameInstance = URoamGameInstance::Get(this))
	{
		if (const URoamWorldDefinition* WorldDefinition = GameInstance->GetWorldDefinition())
		{
			Activities = WorldDefinition->Activities;
		}
	}
	for (const FRoamActivityDef& Def : Activities)
	{
		Runtime.FindOrAdd(Def.ActivityId);
	}
	UE_LOG(LogRoamActivity, Log, TEXT("Activities loaded: %d"), Activities.Num());
}

// ------------------------------------------------------------------------------------------------------------------
// Registry / generation / markers
// ------------------------------------------------------------------------------------------------------------------

const FRoamActivityDef* URoamActivitySubsystem::FindActivity(FName ActivityId) const
{
	return Activities.FindByPredicate([ActivityId](const FRoamActivityDef& A) { return A.ActivityId == ActivityId; });
}

void URoamActivitySubsystem::RegisterActivity(const FRoamActivityDef& Definition)
{
	const int32 Existing = Activities.IndexOfByPredicate([&Definition](const FRoamActivityDef& A) { return A.ActivityId == Definition.ActivityId; });
	if (Existing != INDEX_NONE)
	{
		Activities[Existing] = Definition;
	}
	else
	{
		Activities.Add(Definition);
	}
	Runtime.FindOrAdd(Definition.ActivityId);
}

int32 URoamActivitySubsystem::GenerateDefaultActivities(URoamRoadNetwork* Network)
{
	if (!Network || Network->Roads.Num() == 0)
	{
		return 0;
	}
	if (!Network->IsIndexBuilt())
	{
		Network->BuildSpatialIndex();
	}
	URoamGameInstance* GameInstance = URoamGameInstance::Get(this);
	const URoamWorldDefinition* WorldDefinition = GameInstance ? GameInstance->GetWorldDefinition() : nullptr;

	TArray<FRoamActivityDef> Defs;
	RoamActivity::GenerateDefaultActivityDefs(*Network, WorldDefinition, RoamActivity::FPlacementOptions(), Defs);
	int32 Counts[8] = { 0, 0, 0, 0, 0, 0, 0, 0 };
	for (const FRoamActivityDef& Def : Defs)
	{
		RegisterActivity(Def);
		Counts[FMath::Clamp(static_cast<int32>(Def.Type), 0, 7)]++;
	}
	UE_LOG(LogRoamActivity, Display, TEXT("ROAM_ACTIVITIES_GENERATED total=%d traps=%d zones=%d drift=%d jumps=%d races=%d trials=%d collectibles=%d photos=%d"),
		Defs.Num(), Counts[0], Counts[1], Counts[2], Counts[3], Counts[4], Counts[5], Counts[6], Counts[7]);
	SpawnMarkers();
	return Defs.Num();
}

void URoamActivitySubsystem::ClearActivities()
{
	for (TPair<FName, TObjectPtr<ARoamActivityActor>>& Pair : Markers)
	{
		if (Pair.Value && IsValid(Pair.Value))
		{
			Pair.Value->Destroy();
		}
	}
	Markers.Reset();
	Activities.Reset();
	Runtime.Reset();
	ActiveActivityId = NAME_None;
}

void URoamActivitySubsystem::SpawnMarkers()
{
	UWorld* World = GetWorld();
	if (!World || !bBegunPlay)
	{
		return;
	}
	TSet<FName> Placed;
	for (TActorIterator<ARoamActivityActor> It(World); It; ++It)
	{
		Placed.Add(It->ActivityId);
	}
	FActorSpawnParameters Params;
	Params.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;
	for (const FRoamActivityDef& Def : Activities)
	{
		if (Def.Gates.Num() == 0 || Placed.Contains(Def.ActivityId))
		{
			continue;
		}
		if (ARoamActivityMarkerActor* Marker = World->SpawnActor<ARoamActivityMarkerActor>(ARoamActivityMarkerActor::StaticClass(), FTransform(Def.Gates[0].Center), Params))
		{
			Marker->BuildFromDefinition(Def);
			Markers.Add(Def.ActivityId, Marker);
		}
	}
}

bool URoamActivitySubsystem::ResolveActivityTeleport(const FString& Text, FTransform& OutTransform, FString& OutLabel, FString* OutError) const
{
	const FString Query = Text.TrimStartAndEnd();
	const FRoamActivityDef* Found = nullptr;
	if (Query.IsNumeric())
	{
		const int32 Index = FCString::Atoi(*Query) - 1;
		if (Activities.IsValidIndex(Index))
		{
			Found = &Activities[Index];
		}
	}
	else if (!Query.IsEmpty())
	{
		int32 NumMatches = 0;
		for (const FRoamActivityDef& Def : Activities)
		{
			const FString Id = Def.ActivityId.ToString();
			if (Id.Equals(Query, ESearchCase::IgnoreCase))
			{
				Found = &Def;
				NumMatches = 1;
				break;
			}
			if (Id.Contains(Query, ESearchCase::IgnoreCase))
			{
				Found = &Def;
				++NumMatches;
			}
		}
		if (NumMatches != 1)
		{
			Found = nullptr;
		}
	}
	if (!Found || Found->Gates.Num() == 0)
	{
		if (OutError)
		{
			*OutError = FString::Printf(TEXT("unknown activity '%s' (see act.list)"), *Query);
		}
		return false;
	}

	const FRoamGate& Gate = Found->Gates[0];
	const float Back = (Found->Type == ERoamActivityType::SpeedTrap || Found->Type == ERoamActivityType::DangerSign) ? 40000.0f : 15000.0f;
	FVector Position = Gate.Center - Gate.Forward.GetSafeNormal() * Back;
	FVector Heading = Gate.Forward;
	if (URoamGameInstance* GameInstance = URoamGameInstance::Get(this))
	{
		if (const URoamRoadNetwork* Network = GameInstance->GetRoadNetwork())
		{
			FRoamRoadHit Hit;
			if (!Found->RoadId.IsNone() && Network->SamplePosition(Found->RoadId, FMath::Max(0.0f, Found->RoadS - Back), Hit))
			{
				const FRoamRoad* Road = Network->FindRoad(Found->RoadId);
				Position = (Road && Road->LanesForward > 0) ? Network->GetLanePosition(Hit, 1) : Hit.Position;
				Heading = Hit.Tangent;
			}
		}
	}
	if (UWorld* World = GetWorld())
	{
		FHitResult Hit;
		if (World->LineTraceSingleByChannel(Hit, Position + FVector(0.0, 0.0, 3000.0), Position - FVector(0.0, 0.0, 10000.0), RoamCollision::TraceWheel))
		{
			Position.Z = Hit.ImpactPoint.Z + 60.0;
		}
		else
		{
			Position.Z += 60.0;
		}
	}
	OutTransform = FTransform(FRotator(0.0f, static_cast<float>(FMath::RadiansToDegrees(FMath::Atan2(Heading.Y, Heading.X))), 0.0f), Position);
	OutLabel = Found->DisplayName.IsEmpty() ? Found->ActivityId.ToString() : Found->DisplayName.ToString();
	return true;
}

// ------------------------------------------------------------------------------------------------------------------
// Tracking
// ------------------------------------------------------------------------------------------------------------------

void URoamActivitySubsystem::SetTrackedVehicle(ARoamVehicle* Vehicle)
{
	TrackedOverride = Vehicle;
	bHavePrev = false;
}

ARoamVehicle* URoamActivitySubsystem::GetTrackedVehicle() const
{
	if (ARoamVehicle* Override = TrackedOverride.Get())
	{
		return Override;
	}
	return ARoamVehicle::GetPlayerVehicle(this);
}

bool URoamActivitySubsystem::MakeSample(ARoamVehicle* Vehicle, FRoamActivitySample& OutSample) const
{
	const UWorld* World = GetWorld();
	if (!Vehicle || !World)
	{
		return false;
	}
	const FRoamVehicleTelemetry& T = Vehicle->GetTelemetry();
	OutSample.Time = World->GetTimeSeconds();
	OutSample.Position = Vehicle->GetActorLocation();
	OutSample.VelocityCmS = T.VelocityCmS;
	OutSample.bHasVelocity = !T.VelocityCmS.IsNearlyZero(1.0);
	OutSample.Forward = T.ForwardAxis.IsNearlyZero() ? Vehicle->GetActorForwardVector() : T.ForwardAxis;
	OutSample.Up = T.UpAxis.IsNearlyZero() ? Vehicle->GetActorUpVector() : T.UpAxis;
	OutSample.WheelsOnGround = T.NumWheelsOnGround;
	return true;
}

void URoamActivitySubsystem::BindVehicle(ARoamVehicle* Vehicle)
{
	UnbindVehicle();
	if (!Vehicle)
	{
		return;
	}
	BoundVehicle = Vehicle;
	ImpactHandle = Vehicle->OnImpact.AddUObject(this, &URoamActivitySubsystem::HandleVehicleImpact);
	RecoveredHandle = Vehicle->OnRecovered.AddUObject(this, &URoamActivitySubsystem::HandleVehicleRecovered);
	CarAppliedHandle = Vehicle->OnCarApplied.AddUObject(this, &URoamActivitySubsystem::HandleCarApplied);
}

void URoamActivitySubsystem::UnbindVehicle()
{
	if (ARoamVehicle* Vehicle = BoundVehicle.Get())
	{
		Vehicle->OnImpact.Remove(ImpactHandle);
		Vehicle->OnRecovered.Remove(RecoveredHandle);
		Vehicle->OnCarApplied.Remove(CarAppliedHandle);
	}
	ImpactHandle.Reset();
	RecoveredHandle.Reset();
	CarAppliedHandle.Reset();
	BoundVehicle = nullptr;
}

void URoamActivitySubsystem::HandleVehicleImpact(ARoamVehicle* Vehicle, float ImpactSpeedMs)
{
	(void)Vehicle;
	if (ActiveActivityId.IsNone())
	{
		return;
	}
	const FRoamActivityDef* Def = FindActivity(ActiveActivityId);
	FActivityRuntime* RT = Runtime.Find(ActiveActivityId);
	if (!Def || !RT)
	{
		return;
	}
	if (Def->Type == ERoamActivityType::DriftZone && ImpactSpeedMs >= 7.0f)
	{
		RT->Drift.LoseChain(); // chain loss on crash; banked chains stay
	}
	else if (Def->Type == ERoamActivityType::DangerSign && RT->JumpPhase >= 1 && ImpactSpeedMs >= 15.0f)
	{
		FailAttempt(*Def, TEXT("CRASH LANDING"), TEXT("LAND ON ALL FOUR WHEELS"));
	}
}

void URoamActivitySubsystem::HandleVehicleRecovered(ARoamVehicle* Vehicle)
{
	NotifyVehicleTeleported(Vehicle);
}

void URoamActivitySubsystem::HandleCarApplied(ARoamVehicle* Vehicle)
{
	NotifyCarChanged(Vehicle);
}

void URoamActivitySubsystem::Tick(float DeltaTime)
{
	Super::Tick(DeltaTime);
	if (Activities.Num() == 0)
	{
		return;
	}
	ARoamVehicle* Vehicle = GetTrackedVehicle();
	if (!Vehicle)
	{
		bHavePrev = false;
		return;
	}
	if (Vehicle != BoundVehicle.Get())
	{
		BindVehicle(Vehicle);
		bHavePrev = false;
	}
	FRoamActivitySample Sample;
	if (MakeSample(Vehicle, Sample))
	{
		ProcessSample(Sample);
	}
}

// ------------------------------------------------------------------------------------------------------------------
// State helpers
// ------------------------------------------------------------------------------------------------------------------

ERoamActivityState URoamActivitySubsystem::GetActivityState(FName ActivityId) const
{
	const FActivityRuntime* RT = Runtime.Find(ActivityId);
	return RT ? RT->State : ERoamActivityState::Idle;
}

void URoamActivitySubsystem::SetState(FName ActivityId, ERoamActivityState NewState, double CooldownUntil)
{
	FActivityRuntime& RT = Runtime.FindOrAdd(ActivityId);
	RT.CooldownUntil = CooldownUntil;
	if (RT.State == NewState)
	{
		return;
	}
	RT.State = NewState;
	OnActivityStateChanged.Broadcast(ActivityId, NewState);
}

void URoamActivitySubsystem::CancelActive(const FText& Reason)
{
	if (ActiveActivityId.IsNone())
	{
		return;
	}
	const FName Cancelled = ActiveActivityId;
	ActiveActivityId = NAME_None;
	SetState(Cancelled, ERoamActivityState::Cooldown, Prev.Time + 2.0);
	OnActivityActive.Broadcast(Cancelled, false, FBox(ForceInit));

	FRoamActivityResult Result;
	Result.ActivityId = Cancelled;
	if (const FRoamActivityDef* Def = FindActivity(Cancelled))
	{
		Result.Type = Def->Type;
	}
	Result.bCompleted = false;
	Result.FailReason = Reason;
	LastResult = Result;
	OnActivityResult.Broadcast(Result);
	if (URoamUISubsystem* UI = URoamUISubsystem::Get(this))
	{
		UI->PushNotification(FText::FromString(TEXT("ACTIVITY CANCELLED")), Reason, FLinearColor(1.0f, 0.35f, 0.3f, 1.0f), 2.0f);
	}
	UE_LOG(LogRoamActivity, Display, TEXT("ROAM_ACTIVITY_CANCELLED %s: %s"), *Cancelled.ToString(), *Reason.ToString());
}

void URoamActivitySubsystem::NotifyVehicleTeleported(ARoamVehicle* Vehicle)
{
	(void)Vehicle;
	CancelActive(FText::FromString(TEXT("Vehicle moved")));
	bHavePrev = false;
}

void URoamActivitySubsystem::NotifyCarChanged(ARoamVehicle* Vehicle)
{
	(void)Vehicle;
	CancelActive(FText::FromString(TEXT("Car changed")));
}

void URoamActivitySubsystem::Notify(ERoamNotifyKind Kind, const FString& Title, const FString& Body, const FLinearColor& Color, float Seconds)
{
	if (URoamUISubsystem* UI = URoamUISubsystem::Get(this))
	{
		FRoamNotification Notification;
		Notification.Kind = Kind;
		Notification.Title = FText::FromString(Title);
		Notification.Body = FText::FromString(Body);
		Notification.Color = Color;
		Notification.Seconds = Seconds;
		UI->PushNotification(Notification);
	}
}

FString URoamActivitySubsystem::FormatValue(const FRoamActivityDef& Def, float Value) const
{
	switch (Def.Type)
	{
	case ERoamActivityType::SpeedTrap:
	case ERoamActivityType::SpeedZone:
		return FString::Printf(TEXT("%.0f km/h"), Value);
	case ERoamActivityType::DriftZone:
		return FString::Printf(TEXT("%d PTS"), FMath::RoundToInt(Value));
	case ERoamActivityType::DangerSign:
		return FString::Printf(TEXT("%.1f m"), Value);
	case ERoamActivityType::CheckpointRace:
	case ERoamActivityType::TimeTrial:
		return RoamActivity::FormatTime(Value);
	default:
		return FString::Printf(TEXT("%.1f"), Value);
	}
}

float URoamActivitySubsystem::DistanceToRoute(const FRoamActivityDef& Def, const FVector& Position)
{
	float Best = TNumericLimits<float>::Max();
	for (int32 i = 0; i + 1 < Def.RoutePoints.Num(); ++i)
	{
		Best = FMath::Min(Best, static_cast<float>(FMath::PointDistToSegment(Position, Def.RoutePoints[i], Def.RoutePoints[i + 1])));
	}
	return Def.RoutePoints.Num() >= 2 ? Best : 0.0f;
}

void URoamActivitySubsystem::ShowApproach(const FRoamActivityDef& Def)
{
	const FLinearColor Color = RoamActivity::TypeColor(Def.Type);
	const FString Title = RoamActivity::TypeTitle(Def.Type);
	switch (Def.Type)
	{
	case ERoamActivityType::SpeedTrap:
		Notify(ERoamNotifyKind::Toast, Title, FString::Printf(TEXT("3 STARS AT %.0f km/h"), Def.StarThresholds.Z), Color, 2.5f);
		break;
	case ERoamActivityType::SpeedZone:
		Notify(ERoamNotifyKind::Toast, Title, FString::Printf(TEXT("AVERAGE %.0f km/h FOR 3 STARS"), Def.StarThresholds.Z), Color, 2.5f);
		break;
	case ERoamActivityType::DriftZone:
		Notify(ERoamNotifyKind::Toast, Title, FString::Printf(TEXT("%.0f PTS FOR 3 STARS"), Def.StarThresholds.Z), Color, 2.5f);
		break;
	case ERoamActivityType::DangerSign:
		Notify(ERoamNotifyKind::Toast, Title, FString::Printf(TEXT("%.0f m FOR 3 STARS"), Def.StarThresholds.Z), Color, 2.5f);
		break;
	case ERoamActivityType::CheckpointRace:
	case ERoamActivityType::TimeTrial:
		Notify(ERoamNotifyKind::Toast, Title, FString::Printf(TEXT("DRIVE THROUGH THE START GATE  -  GOLD %s"), *RoamActivity::FormatTime(Def.StarThresholds.Z)), Color, 2.5f);
		break;
	default:
		break;
	}
}

// ------------------------------------------------------------------------------------------------------------------
// Core: sample processing
// ------------------------------------------------------------------------------------------------------------------

void URoamActivitySubsystem::ProcessSample(const FRoamActivitySample& Input)
{
	FRoamActivitySample S = Input;
	if (!bHavePrev)
	{
		Prev = S;
		bHavePrev = true;
		return;
	}
	const double Dt = S.Time - Prev.Time;
	if (Dt <= 1.0e-6)
	{
		return;
	}
	const FVector A = Prev.Position;
	const FVector B = S.Position;
	if (Dt > 2.0 || FVector::DistSquared(A, B) > MaxSegmentCm * MaxSegmentCm)
	{
		// Teleport / respawn / long hitch: no tunnelling artefacts, no half-finished attempts.
		CancelActive(FText::FromString(TEXT("Vehicle moved")));
		Prev = S;
		return;
	}
	if (!S.bHasVelocity)
	{
		S.VelocityCmS = (B - A) / Dt;
		S.bHasVelocity = true;
	}

	if (!ActiveActivityId.IsNone())
	{
		UpdateActive(S, Dt);
	}
	for (int32 i = 0; i < Activities.Num(); ++i)
	{
		const FRoamActivityDef& Def = Activities[i];
		if (Def.Gates.Num() == 0)
		{
			continue;
		}
		FActivityRuntime& RT = Runtime.FindOrAdd(Def.ActivityId);
		if ((RT.State == ERoamActivityState::Result || RT.State == ERoamActivityState::Cooldown) && S.Time >= RT.CooldownUntil)
		{
			SetState(Def.ActivityId, ERoamActivityState::Idle);
		}
		TryStart(Def, RT, S, Dt);
	}
	Prev = S;
}

void URoamActivitySubsystem::TryStart(const FRoamActivityDef& Def, FActivityRuntime& RT, const FRoamActivitySample& S, double Dt)
{
	if (RT.State != ERoamActivityState::Idle || RT.bDone)
	{
		return;
	}
	const FRoamGate& G0 = Def.Gates[0];
	const FVector A = Prev.Position;
	const FVector B = S.Position;
	const double SegLen = FVector::Dist(A, B);

	if (!RT.bApproachShown && FVector::DistSquared(B, G0.Center) < 50000.0 * 50000.0)
	{
		RT.bApproachShown = true;
		ShowApproach(Def);
	}

	RoamActivity::FGateCrossing X;
	const auto Crosses = [&](const FRoamGate& Gate, bool bAllowReverse) -> bool
	{
		const double Reach = SegLen + Gate.HalfWidthCm + Gate.HalfHeightCm + 50.0;
		return FVector::DistSquared(B, Gate.Center) <= Reach * Reach && RoamActivity::SegmentCrossesGate(Gate, A, B, X, bAllowReverse);
	};

	switch (Def.Type)
	{
	case ERoamActivityType::SpeedTrap:
		if (Crosses(G0, false))
		{
			const float Speed = FMath::Lerp(Prev.GetSpeedKmh(), S.GetSpeedKmh(), X.Alpha);
			FinishAttempt(Def, Speed);
		}
		break;

	case ERoamActivityType::SpeedZone:
	case ERoamActivityType::DriftZone:
		if (ActiveActivityId.IsNone() && Def.Gates.Num() >= 2)
		{
			if (Crosses(G0, false))
			{
				BeginAttempt(Def, RT, Prev.Time + Dt * X.Alpha, 1);
				RT.PathCm = static_cast<float>(SegLen) * (1.0f - X.Alpha);
			}
			else if (Crosses(Def.Gates[1], true) && !X.bForward)
			{
				BeginAttempt(Def, RT, Prev.Time + Dt * X.Alpha, -1);
				RT.PathCm = static_cast<float>(SegLen) * (1.0f - X.Alpha);
			}
		}
		break;

	case ERoamActivityType::DangerSign:
		if (ActiveActivityId.IsNone() && Crosses(G0, false) && FMath::Lerp(Prev.GetSpeedKmh(), S.GetSpeedKmh(), X.Alpha) >= 40.0f)
		{
			BeginAttempt(Def, RT, Prev.Time + Dt * X.Alpha, 1);
			RT.TakeoffPos = B;
		}
		break;

	case ERoamActivityType::CheckpointRace:
	case ERoamActivityType::TimeTrial:
		if (ActiveActivityId.IsNone() && Def.Gates.Num() >= 2 && S.GetSpeedKmh() > 3.0f && Crosses(G0, false))
		{
			BeginAttempt(Def, RT, Prev.Time + Dt * X.Alpha, 1);
		}
		break;

	case ERoamActivityType::Collectible:
	case ERoamActivityType::PhotoSpot:
	{
		const float Distance = static_cast<float>(FMath::PointDistToSegment(G0.Center, A, B));
		const float Speed = S.GetSpeedKmh();
		const bool bSpeedOk = Def.Type == ERoamActivityType::Collectible ? Speed >= 20.0f : Speed <= 50.0f;
		if (Distance <= G0.HalfWidthCm && bSpeedOk)
		{
			RT.bDone = true;
			URoamSaveSubsystem* Save = GetSave(GetWorld());
			const bool bFirstTime = Save ? Save->MarkCollected(Def.ActivityId) : true;
			if (bFirstTime)
			{
				if (Save)
				{
					Save->AddXp(Def.XpReward);
				}
				Notify(ERoamNotifyKind::Toast, RoamActivity::TypeTitle(Def.Type), FString::Printf(TEXT("+%d XP"), Def.XpReward), RoamActivity::TypeColor(Def.Type), 2.5f);
				UE_LOG(LogRoamActivity, Display, TEXT("ROAM_ACTIVITY_COLLECTED %s"), *Def.ActivityId.ToString());
			}
			SetState(Def.ActivityId, ERoamActivityState::Result, S.Time + 3.0);
		}
		break;
	}
	default:
		break;
	}
}

void URoamActivitySubsystem::BeginAttempt(const FRoamActivityDef& Def, FActivityRuntime& RT, double StartTime, int32 Direction)
{
	ActiveActivityId = Def.ActivityId;
	RT.StartTime = StartTime;
	RT.Direction = Direction;
	RT.NextGate = 1;
	RT.PathCm = 0.0f;
	RT.StoppedSec = 0.0f;
	RT.WrongWaySec = 0.0f;
	RT.OffRouteSec = 0.0f;
	RT.LiveValue = 0.0f;
	RT.Splits.Reset();
	RT.Drift.Reset();
	RT.JumpPhase = 0;
	RT.AirSec = 0.0f;
	RT.FlightSec = 0.0f;
	RT.ValidateSec = 0.0f;
	RT.JumpDistanceCm = 0.0f;

	FBox Bounds(ForceInit);
	for (const FRoamGate& Gate : Def.Gates)
	{
		Bounds += Gate.Center;
	}
	for (const FVector& Point : Def.RoutePoints)
	{
		Bounds += Point;
	}
	SetState(Def.ActivityId, Def.Type == ERoamActivityType::DangerSign ? ERoamActivityState::Armed : ERoamActivityState::Active);
	OnActivityActive.Broadcast(Def.ActivityId, true, Bounds);

	const FLinearColor Color = RoamActivity::TypeColor(Def.Type);
	switch (Def.Type)
	{
	case ERoamActivityType::SpeedZone:
		Notify(ERoamNotifyKind::Toast, TEXT("SPEED ZONE"), TEXT("KEEP YOUR AVERAGE UP"), Color, 2.0f);
		break;
	case ERoamActivityType::DriftZone:
		Notify(ERoamNotifyKind::Toast, TEXT("DRIFT ZONE"), TEXT("SLIDE FOR POINTS"), Color, 2.0f);
		break;
	case ERoamActivityType::DangerSign:
		Notify(ERoamNotifyKind::Toast, TEXT("DANGER SIGN"), TEXT("FULL THROTTLE"), Color, 2.0f);
		break;
	case ERoamActivityType::CheckpointRace:
	case ERoamActivityType::TimeTrial:
	{
		float Best = 0.0f;
		const FString BestText = GetBestValue(Def.ActivityId, Best) ? FString::Printf(TEXT("   BEST %s"), *RoamActivity::FormatTime(Best)) : FString();
		Notify(ERoamNotifyKind::Banner, RoamActivity::TypeTitle(Def.Type), FString::Printf(TEXT("%d CHECKPOINTS%s"), Def.Gates.Num() - 1, *BestText), Color, 3.5f);
		break;
	}
	default:
		break;
	}
	UE_LOG(LogRoamActivity, Display, TEXT("ROAM_ACTIVITY_STARTED %s"), *Def.ActivityId.ToString());
}

void URoamActivitySubsystem::UpdateActive(const FRoamActivitySample& S, double Dt)
{
	const FRoamActivityDef* Def = FindActivity(ActiveActivityId);
	FActivityRuntime* RT = Runtime.Find(ActiveActivityId);
	if (!Def || !RT || Def->Gates.Num() == 0)
	{
		ActiveActivityId = NAME_None;
		return;
	}
	switch (Def->Type)
	{
	case ERoamActivityType::SpeedZone:
	case ERoamActivityType::DriftZone:
		UpdateZone(*Def, *RT, S, Dt);
		break;
	case ERoamActivityType::DangerSign:
		UpdateJump(*Def, *RT, S, Dt);
		break;
	case ERoamActivityType::CheckpointRace:
	case ERoamActivityType::TimeTrial:
		UpdateChain(*Def, *RT, S, Dt);
		break;
	default:
		ActiveActivityId = NAME_None;
		break;
	}
}

void URoamActivitySubsystem::UpdateZone(const FRoamActivityDef& Def, FActivityRuntime& RT, const FRoamActivitySample& S, double Dt)
{
	const FVector A = Prev.Position;
	const FVector B = S.Position;
	const float SegLen = static_cast<float>(FVector::Dist(A, B));
	const float Dtf = static_cast<float>(Dt);
	const float SpeedKmh = S.GetSpeedKmh();
	const bool bDrift = Def.Type == ERoamActivityType::DriftZone;
	const float Elapsed = static_cast<float>(S.Time - RT.StartTime);
	RT.PathCm += SegLen;

	if (bDrift)
	{
		const FVector Vh = Flat(S.VelocityCmS);
		const FVector Fh = Flat(S.Forward);
		float Slip = 0.0f;
		if (S.VelocityCmS.SizeSquared2D() > 100.0 * 100.0 && !Vh.IsNearlyZero() && !Fh.IsNearlyZero())
		{
			Slip = FMath::RadiansToDegrees(FMath::Acos(FMath::Clamp(static_cast<float>(FVector::DotProduct(Vh, Fh)), -1.0f, 1.0f)));
			if (Slip > 90.0f)
			{
				Slip = 0.0f; // reversing: not a drift
			}
		}
		RT.Drift.Step(FMath::Min(Dtf, 0.1f), SpeedKmh, Slip, S.WheelsOnGround >= 3);
		RT.LiveValue = RT.Drift.GetTotal();
	}
	else
	{
		RT.LiveValue = Elapsed > 0.2f ? RT.PathCm * 0.036f / Elapsed : 0.0f;
	}

	const FRoamGate& StartGate = RT.Direction > 0 ? Def.Gates[0] : Def.Gates[1];
	const FRoamGate& EndGate = RT.Direction > 0 ? Def.Gates[1] : Def.Gates[0];
	RoamActivity::FGateCrossing X;
	if (RoamActivity::SegmentCrossesGate(EndGate, A, B, X, true) && X.bForward == (RT.Direction > 0))
	{
		if (bDrift)
		{
			RT.Drift.BankChain();
			FinishAttempt(Def, RT.Drift.ZoneScore);
			return;
		}
		const float EndElapsed = static_cast<float>(Prev.Time + Dt * X.Alpha - RT.StartTime);
		const float Path = RT.PathCm - SegLen * (1.0f - X.Alpha);
		FinishAttempt(Def, EndElapsed > 0.05f ? Path * 0.036f / EndElapsed : 0.0f);
		return;
	}

	if (Elapsed > 900.0f)
	{
		CancelActive(FText::FromString(TEXT("Timed out")));
		return;
	}
	RT.StoppedSec = SpeedKmh < (bDrift ? 5.0f : 10.0f) ? RT.StoppedSec + Dtf : 0.0f;
	if (RT.StoppedSec > (bDrift ? 6.0f : 2.5f))
	{
		FailAttempt(Def, TEXT("STOPPED"), bDrift ? TEXT("KEEP DRIFTING") : TEXT("KEEP YOUR SPEED UP"));
		return;
	}
	if (!bDrift)
	{
		const FVector Direction = Flat(EndGate.Center - StartGate.Center);
		const bool bWrongWay = SpeedKmh > 10.0f && !Direction.IsNearlyZero() && FVector::DotProduct(Flat(S.VelocityCmS), Direction) < 0.0;
		RT.WrongWaySec = bWrongWay ? RT.WrongWaySec + Dtf : 0.0f;
		if (RT.WrongWaySec > 1.5f)
		{
			FailAttempt(Def, TEXT("WRONG WAY"), TEXT("DRIVE TOWARD THE END GATE"));
			return;
		}
	}
	if (Def.RoutePoints.Num() >= 2)
	{
		const float OffRoute = DistanceToRoute(Def, B);
		RT.OffRouteSec = OffRoute > (bDrift ? 6000.0f : 1600.0f) ? RT.OffRouteSec + Dtf : 0.0f;
		if (RT.OffRouteSec > (bDrift ? 3.0f : 2.0f))
		{
			FailAttempt(Def, bDrift ? TEXT("LEFT THE ZONE") : TEXT("LEFT THE ROAD"), TEXT("STAY ON THE ROUTE"));
		}
	}
}

void URoamActivitySubsystem::UpdateJump(const FRoamActivityDef& Def, FActivityRuntime& RT, const FRoamActivitySample& S, double Dt)
{
	const float Dtf = static_cast<float>(Dt);
	const FVector B = S.Position;
	const bool bAirborne = S.WheelsOnGround <= 0;

	const auto Disarm = [&]()
	{
		ActiveActivityId = NAME_None;
		OnActivityActive.Broadcast(Def.ActivityId, false, FBox(ForceInit));
		SetState(Def.ActivityId, ERoamActivityState::Cooldown, S.Time + 1.5);
	};

	if (RT.JumpPhase == 0)
	{
		const float Window = GetParam(Def, TEXT("LaunchWindowCm"), 9000.0f);
		const float Along = static_cast<float>(FVector::DotProduct(B - Def.Gates[0].Center, Def.Gates[0].Forward.GetSafeNormal()));
		if (bAirborne)
		{
			RT.AirSec += Dtf;
		}
		else
		{
			RT.AirSec = 0.0f;
			RT.TakeoffPos = B;
		}
		if (RT.AirSec >= 0.12f)
		{
			RT.JumpPhase = 1;
			RT.FlightSec = RT.AirSec;
			SetState(Def.ActivityId, ERoamActivityState::Active);
		}
		else if (Along > Window || S.Time - RT.StartTime > 20.0)
		{
			Disarm();
		}
		return;
	}

	const float Horizontal = static_cast<float>(FVector::Dist2D(B, RT.TakeoffPos));
	if (RT.JumpPhase == 1)
	{
		RT.FlightSec += Dtf;
		RT.LiveValue = Horizontal * 0.01f;
		if (S.Up.Z < 0.0f)
		{
			FailAttempt(Def, TEXT("FLIPPED"), TEXT("LAND ON ALL FOUR WHEELS"));
		}
		else if (RT.FlightSec > 12.0f)
		{
			FailAttempt(Def, TEXT("CRASH LANDING"), TEXT("FLIGHT TOO LONG"));
		}
		else if (S.WheelsOnGround >= 2)
		{
			if (RT.FlightSec < 0.4f)
			{
				Disarm(); // a hop, not a jump
			}
			else
			{
				RT.JumpDistanceCm = Horizontal;
				RT.JumpPhase = 2;
				RT.ValidateSec = 0.0f;
				if (S.Up.Z < 0.5f)
				{
					FailAttempt(Def, TEXT("CRASH LANDING"), TEXT("LAND ON ALL FOUR WHEELS"));
				}
			}
		}
		return;
	}

	RT.ValidateSec += Dtf;
	RT.LiveValue = RT.JumpDistanceCm * 0.01f;
	if (S.Up.Z < 0.0f)
	{
		FailAttempt(Def, TEXT("FLIPPED"), TEXT("LAND ON ALL FOUR WHEELS"));
	}
	else if (RT.ValidateSec >= 1.0f && S.Up.Z < 0.7f)
	{
		FailAttempt(Def, TEXT("CRASH LANDING"), TEXT("LAND ON ALL FOUR WHEELS"));
	}
	else if (RT.ValidateSec >= 1.5f)
	{
		FinishAttempt(Def, RT.JumpDistanceCm * 0.01f);
	}
}

void URoamActivitySubsystem::UpdateChain(const FRoamActivityDef& Def, FActivityRuntime& RT, const FRoamActivitySample& S, double Dt)
{
	const FVector A = Prev.Position;
	const FVector B = S.Position;
	const int32 Last = Def.Gates.Num() - 1;
	const float Dtf = static_cast<float>(Dt);
	const float Elapsed = static_cast<float>(S.Time - RT.StartTime);
	RT.LiveValue = Elapsed;

	RoamActivity::FGateCrossing X;
	if (RT.NextGate <= Last && RoamActivity::SegmentCrossesGate(Def.Gates[RT.NextGate], A, B, X, false))
	{
		const float Split = static_cast<float>(Prev.Time + Dt * X.Alpha - RT.StartTime);
		RT.Splits.Add(Split);
		if (RT.NextGate == Last)
		{
			FinishAttempt(Def, Split);
			return;
		}
		Notify(ERoamNotifyKind::Toast, FString::Printf(TEXT("CHECKPOINT %d / %d"), RT.NextGate, Last - 1), RoamActivity::FormatTime(Split), RoamActivity::TypeColor(Def.Type), 1.8f);
		++RT.NextGate;
		RT.OffRouteSec = 0.0f;
	}

	const float Limit = GetParam(Def, TEXT("TimeLimitSec"), 0.0f);
	if (Limit > 0.0f && Elapsed > Limit)
	{
		FailAttempt(Def, TEXT("TIME UP"), TEXT("TRY AGAIN"));
		return;
	}
	if (Def.RoutePoints.Num() >= 2)
	{
		RT.OffRouteSec = DistanceToRoute(Def, B) > 8000.0f ? RT.OffRouteSec + Dtf : 0.0f;
		if (RT.OffRouteSec > 12.0f)
		{
			FailAttempt(Def, TEXT("OFF COURSE"), TEXT("STAY ON THE ROUTE"));
		}
	}
}

void URoamActivitySubsystem::FinishAttempt(const FRoamActivityDef& Def, float Value)
{
	if (ActiveActivityId == Def.ActivityId)
	{
		ActiveActivityId = NAME_None;
		OnActivityActive.Broadcast(Def.ActivityId, false, FBox(ForceInit));
	}
	SetState(Def.ActivityId, ERoamActivityState::Result, Prev.Time + 3.0);

	FRoamActivityResult Result;
	Result.ActivityId = Def.ActivityId;
	Result.Type = Def.Type;
	Result.Value = Value;
	Result.Stars = RoamActivity::StarsForValue(Def.StarThresholds, Value, Def.bLowerIsBetter);
	Result.XpAwarded = 0;
	Result.bCompleted = true;
	ReportResult(Result);
}

void URoamActivitySubsystem::FailAttempt(const FRoamActivityDef& Def, const FString& Title, const FString& Detail)
{
	if (ActiveActivityId == Def.ActivityId)
	{
		ActiveActivityId = NAME_None;
		OnActivityActive.Broadcast(Def.ActivityId, false, FBox(ForceInit));
	}
	SetState(Def.ActivityId, ERoamActivityState::Cooldown, Prev.Time + 2.0);

	FRoamActivityResult Result;
	Result.ActivityId = Def.ActivityId;
	Result.Type = Def.Type;
	Result.bCompleted = false;
	Result.FailReason = FText::FromString(Title);
	LastResult = Result;
	OnActivityResult.Broadcast(Result);
	Notify(ERoamNotifyKind::Banner, Title, Detail, FLinearColor(1.0f, 0.3f, 0.25f, 1.0f), 2.5f);
	UE_LOG(LogRoamActivity, Display, TEXT("ROAM_ACTIVITY_FAILED %s: %s"), *Def.ActivityId.ToString(), *Title);
}

bool URoamActivitySubsystem::GetLiveInfo(FRoamActivityLiveInfo& OutInfo) const
{
	if (ActiveActivityId.IsNone())
	{
		return false;
	}
	const FRoamActivityDef* Def = FindActivity(ActiveActivityId);
	const FActivityRuntime* RT = Runtime.Find(ActiveActivityId);
	if (!Def || !RT)
	{
		return false;
	}
	OutInfo.ActivityId = Def->ActivityId;
	OutInfo.Type = Def->Type;
	OutInfo.State = RT->State;
	OutInfo.ElapsedSec = static_cast<float>(Prev.Time - RT->StartTime);
	OutInfo.Value = RT->LiveValue;
	OutInfo.StarsNow = RoamActivity::StarsForValue(Def->StarThresholds, RT->LiveValue, Def->bLowerIsBetter);
	OutInfo.Checkpoint = FMath::Max(RT->NextGate - 1, 0);
	OutInfo.NumCheckpoints = FMath::Max(Def->Gates.Num() - 1, 0);
	OutInfo.ChainScore = RT->Drift.ChainScore;
	OutInfo.Multiplier = RT->Drift.Multiplier;
	return true;
}

// ------------------------------------------------------------------------------------------------------------------
// Progress / results
// ------------------------------------------------------------------------------------------------------------------

bool URoamActivitySubsystem::GetBestValue(FName ActivityId, float& OutValue) const
{
	const URoamSaveSubsystem* Save = GetSave(GetWorld());
	return Save && Save->GetPersonalBest(ActivityId, OutValue);
}

int32 URoamActivitySubsystem::GetStars(FName ActivityId) const
{
	const URoamSaveSubsystem* Save = GetSave(GetWorld());
	if (!Save)
	{
		return 0;
	}
	const int32* Stars = Save->GetProfile().ActivityStars.Find(ActivityId);
	return Stars ? *Stars : 0;
}

int32 URoamActivitySubsystem::GetTotalStars() const
{
	int32 Total = 0;
	for (const FRoamActivityDef& Def : Activities)
	{
		Total += GetStars(Def.ActivityId);
	}
	return Total;
}

int32 URoamActivitySubsystem::GetMaxStars() const
{
	int32 Total = 0;
	for (const FRoamActivityDef& Def : Activities)
	{
		if (Def.Type != ERoamActivityType::Collectible && Def.Type != ERoamActivityType::PhotoSpot)
		{
			Total += 3;
		}
	}
	return Total;
}

void URoamActivitySubsystem::ReportResult(const FRoamActivityResult& Result)
{
	FRoamActivityResult Final = Result;
	const FRoamActivityDef* Def = FindActivity(Result.ActivityId);
	URoamSaveSubsystem* Save = GetSave(GetWorld());
	if (Save && Result.bCompleted)
	{
		float PreviousBest = 0.0f;
		const bool bHadBest = Save->GetPersonalBest(Result.ActivityId, PreviousBest);
		const int32 OldStars = GetStars(Result.ActivityId);
		Final.bNewBest = Save->SubmitPersonalBest(Result.ActivityId, Result.Value, Def && Def->bLowerIsBetter);
		Final.DeltaToBest = bHadBest ? Result.Value - PreviousBest : 0.0f;
		Save->SubmitStars(Result.ActivityId, Result.Stars);
		Final.XpAwarded = RoamActivity::XpForStarImprovement(OldStars, Result.Stars, Def ? Def->XpReward : 100);
		Save->AddXp(Final.XpAwarded);
		if (bAutoSaveOnResult && Final.bNewBest)
		{
			Save->AsyncSaveProfile(false);
		}
	}
	LastResult = Final;
	UE_LOG(LogRoamActivity, Display, TEXT("ROAM_ACTIVITY_RESULT %s value=%.2f stars=%d newBest=%d xp=%d"), *Final.ActivityId.ToString(), Final.Value, Final.Stars, Final.bNewBest ? 1 : 0, Final.XpAwarded);

	if (Def && Final.bCompleted)
	{
		const FLinearColor Color = RoamActivity::TypeColor(Def->Type);
		if (Def->Type == ERoamActivityType::SpeedTrap && Final.Stars == 0)
		{
			Notify(ERoamNotifyKind::Toast, TEXT("TOO SLOW"), FString::Printf(TEXT("%.0f km/h NEEDED"), Def->StarThresholds.X), FLinearColor(1.0f, 0.3f, 0.25f, 1.0f), 2.5f);
		}
		else if (URoamUISubsystem* UI = URoamUISubsystem::Get(this))
		{
			float Best = Final.Value;
			if (Save)
			{
				Save->GetPersonalBest(Final.ActivityId, Best);
			}
			FRoamNotification Card;
			Card.Kind = ERoamNotifyKind::ResultCard;
			Card.Title = FText::FromString(RoamActivity::TypeTitle(Def->Type));
			Card.Body = FText::FromString(FString::Printf(TEXT("BEST %s"), *FormatValue(*Def, Best)));
			Card.Value = FText::FromString(FormatValue(*Def, Final.Value));
			Card.Color = Color;
			Card.Stars = Final.Stars;
			Card.bNewBest = Final.bNewBest;
			Card.Seconds = 5.0f;
			UI->PushNotification(Card);
		}
	}
	OnActivityResult.Broadcast(Final);
}

// ------------------------------------------------------------------------------------------------------------------
// Console
// ------------------------------------------------------------------------------------------------------------------

ROAM_REGISTER_CONSOLE_COMMAND_CATEGORY("act.list", "act.list", "List all activities with their stars.", "activities",
	[](const FRoamConsoleContext& Ctx) -> FString
	{
		URoamActivitySubsystem* Activities = Ctx.World ? Ctx.World->GetSubsystem<URoamActivitySubsystem>() : nullptr;
		if (!Activities)
		{
			return Ctx.Fail(TEXT("no activity system (no game world)"));
		}
		FString Text = FString::Printf(TEXT("%d activities, stars %d/%d"), Activities->GetActivities().Num(), Activities->GetTotalStars(), Activities->GetMaxStars());
		int32 Index = 0;
		for (const FRoamActivityDef& Def : Activities->GetActivities())
		{
			float Best = 0.0f;
			const FString BestText = Activities->GetBestValue(Def.ActivityId, Best) ? FString::Printf(TEXT("best %.1f"), Best) : FString(TEXT("-"));
			Text += FString::Printf(TEXT("\n  %2d %-14s %-14s stars %d  thr %.0f/%.0f/%.0f  %s  %s"), ++Index, *Def.ActivityId.ToString(), *Roam::EnumToString(Def.Type),
				Activities->GetStars(Def.ActivityId), Def.StarThresholds.X, Def.StarThresholds.Y, Def.StarThresholds.Z, *BestText, *Def.RoadId.ToString());
		}
		return Text;
	});

ROAM_REGISTER_CONSOLE_COMMAND_CATEGORY("act.tp", "act.tp <n|id>", "Teleport to the start of an activity (1-based index from act.list, id or unique part of it).", "activities",
	[](const FRoamConsoleContext& Ctx) -> FString
	{
		URoamActivitySubsystem* Activities = Ctx.World ? Ctx.World->GetSubsystem<URoamActivitySubsystem>() : nullptr;
		ARoamVehicle* Vehicle = ARoamVehicle::GetPlayerVehicle(Ctx.World);
		if (!Activities || !Vehicle)
		{
			return Ctx.Fail(TEXT("no player vehicle / activity system"));
		}
		if (Ctx.NumArgs() == 0)
		{
			return Ctx.Fail(TEXT("usage: act.tp <n|id>   (see act.list)"));
		}
		FTransform Target;
		FString Label;
		FString Error;
		if (!Activities->ResolveActivityTeleport(Ctx.JoinFrom(0), Target, Label, &Error))
		{
			return Ctx.Fail(Error);
		}
		Vehicle->TeleportVehicle(Target, false);
		return FString::Printf(TEXT("teleported to %s (%.0f, %.0f, %.0f)"), *Label, Target.GetLocation().X, Target.GetLocation().Y, Target.GetLocation().Z);
	});

ROAM_REGISTER_CONSOLE_COMMAND_CATEGORY("act.gen", "act.gen", "Clear and regenerate the default activities on the configured road network.", "activities",
	[](const FRoamConsoleContext& Ctx) -> FString
	{
		URoamActivitySubsystem* Activities = Ctx.World ? Ctx.World->GetSubsystem<URoamActivitySubsystem>() : nullptr;
		URoamGameInstance* GameInstance = Cast<URoamGameInstance>(Ctx.GameInstance);
		URoamRoadNetwork* Network = GameInstance ? GameInstance->GetRoadNetwork() : nullptr;
		if (!Activities || !Network)
		{
			return Ctx.Fail(TEXT("no activity system / no road network configured"));
		}
		Activities->ClearActivities();
		const int32 Count = Activities->GenerateDefaultActivities(Network);
		return FString::Printf(TEXT("generated %d activities"), Count);
	});

ROAM_REGISTER_CONSOLE_COMMAND_CATEGORY("act.synth", "act.synth", "Replace the activities with the default set generated on a synthetic grid road network (test map, no world data needed).", "activities",
	[](const FRoamConsoleContext& Ctx) -> FString
	{
		URoamActivitySubsystem* Activities = Ctx.World ? Ctx.World->GetSubsystem<URoamActivitySubsystem>() : nullptr;
		if (!Activities)
		{
			return Ctx.Fail(TEXT("no activity system (no game world)"));
		}
		URoamRoadNetwork* Network = URoamRoadNetwork::BuildGeneratedForTests(Activities, 3, 100000.0f, 500.0f);
		Activities->ClearActivities();
		const int32 Count = Activities->GenerateDefaultActivities(Network);
		return FString::Printf(TEXT("generated %d activities on a synthetic network (see act.list)"), Count);
	});
