// Copyright Epic Games, Inc. All Rights Reserved.

#include "Vehicle/RoamAutoDrive.h"

#include "Components/StaticMeshComponent.h"
#include "Console/RoamConsoleSubsystem.h"
#include "Core/RoamCollision.h"
#include "Core/RoamGameInstance.h"
#include "Core/RoamGameMode.h"
#include "Core/RoamLog.h"
#include "Data/RoamCarCatalog.h"
#include "Data/RoamCarDefinition.h"
#include "Data/RoamRoadNetwork.h"
#include "Engine/World.h"
#include "GameFramework/PlayerController.h"
#include "HAL/PlatformTime.h"
#include "Vehicle/RoamVehicle.h"
#include "Vehicle/RoamVehicleMovement.h"
#include "Vehicle/RoamVehicleVisuals.h"

namespace
{
	/** The scenic loop as a sequence of road base names (Docs/WORLD_DATA_FORMATS.md 6.5); edges are split as "NAME#k". */
	const TCHAR* const GLoopSequence[] = { TEXT("HWY_EAST"), TEXT("LOOP_COAST"), TEXT("LOOP_SOUTH"), TEXT("LOOP_VALLEY"), TEXT("LOOP_PASS"), TEXT("LOOP_DESC") };
	constexpr int32 GNumLoopRoads = UE_ARRAY_COUNT(GLoopSequence);

	FName BaseRoadName(const FName RoadId)
	{
		FString Text = RoadId.ToString();
		int32 HashIndex = INDEX_NONE;
		if (Text.FindChar(TEXT('#'), HashIndex))
		{
			Text.LeftInline(HashIndex);
		}
		return FName(*Text);
	}

	bool GroundBelow(UWorld* World, const AActor* Ignore, const FVector& Location, float& OutZ, FVector* OutNormal = nullptr)
	{
		if (!World)
		{
			return false;
		}
		FHitResult Hit;
		FCollisionQueryParams Params(SCENE_QUERY_STAT(RoamAutoDriveGround), false, Ignore);
		if (World->LineTraceSingleByChannel(Hit, Location + FVector(0.0, 0.0, 200.0), Location - FVector(0.0, 0.0, 600.0), RoamCollision::TraceWheel, Params))
		{
			OutZ = static_cast<float>(Hit.ImpactPoint.Z);
			if (OutNormal)
			{
				*OutNormal = FVector(Hit.ImpactNormal);
			}
			return true;
		}
		return false;
	}

	FString FloatArray4(const float* Values, bool bWholeNumbers = false)
	{
		if (bWholeNumbers)
		{
			return FString::Printf(TEXT("[%.0f %.0f %.0f %.0f]"), Values[0], Values[1], Values[2], Values[3]);
		}
		return FString::Printf(TEXT("[%.1f %.1f %.1f %.1f]"), Values[0], Values[1], Values[2], Values[3]);
	}
}

URoamAutoDriveSubsystem* URoamAutoDriveSubsystem::Get(const UObject* WorldContext)
{
	const UWorld* World = WorldContext ? WorldContext->GetWorld() : nullptr;
	return World ? World->GetSubsystem<URoamAutoDriveSubsystem>() : nullptr;
}

bool URoamAutoDriveSubsystem::DoesSupportWorldType(const EWorldType::Type WorldType) const
{
	return WorldType == EWorldType::Game || WorldType == EWorldType::PIE;
}

void URoamAutoDriveSubsystem::Deinitialize()
{
	bActive = false;
	CarTest.Phase = ECarTestPhase::Idle;
	Super::Deinitialize();
}

// ------------------------------------------------------------------------------------------------------------------
// Road graph helpers
// ------------------------------------------------------------------------------------------------------------------

bool URoamAutoDriveSubsystem::EnsureNetwork()
{
	if (Network && bCachesBuilt)
	{
		return true;
	}
	URoamGameInstance* GameInstance = URoamGameInstance::Get(this);
	Network = GameInstance ? GameInstance->GetRoadNetwork() : nullptr;
	if (!Network || Network->GetNumRoads() == 0)
	{
		Network = nullptr;
		return false;
	}
	BuildRoadCaches();
	return true;
}

void URoamAutoDriveSubsystem::BuildRoadCaches()
{
	RoadLoopIndex.SetNum(Network->Roads.Num());
	RoadBaseName.SetNum(Network->Roads.Num());
	for (int32 i = 0; i < Network->Roads.Num(); ++i)
	{
		RoadBaseName[i] = BaseRoadName(Network->Roads[i].RoadId);
		RoadLoopIndex[i] = INDEX_NONE;
		for (int32 k = 0; k < GNumLoopRoads; ++k)
		{
			if (RoadBaseName[i] == FName(GLoopSequence[k]))
			{
				RoadLoopIndex[i] = k;
				break;
			}
		}
	}
	// vertical profile: the generated roads contain short crests (second derivative up to -0.08 1/m = radius 12 m) that launch a car at 60 km/h.
	// Precompute the speed each 2 m bucket allows (centripetal acceleration <= 0.5 g keeps half of the wheel load).
	RoadCrestLimit.SetNum(Network->Roads.Num());
	for (int32 RoadIdx = 0; RoadIdx < Network->Roads.Num(); ++RoadIdx)
	{
		const FRoamRoad& Road = Network->Roads[RoadIdx];
		TArray<float>& Limit = RoadCrestLimit[RoadIdx];
		Limit.Init(1.0e6f, FMath::Max(2, FMath::CeilToInt(Road.LengthCm / 200.0f) + 2));
		for (int32 i = 1; i + 1 < Road.Samples.Num(); ++i)
		{
			const double H1 = 0.01 * (Road.Samples[i].S - Road.Samples[i - 1].S);
			const double H2 = 0.01 * (Road.Samples[i + 1].S - Road.Samples[i].S);
			if (H1 < 0.2 || H2 < 0.2)
			{
				continue;
			}
			const double Z0 = 0.01 * Road.Samples[i - 1].Position.Z;
			const double Z1 = 0.01 * Road.Samples[i].Position.Z;
			const double Z2 = 0.01 * Road.Samples[i + 1].Position.Z;
			const double Curvature = -2.0 * ((Z2 - Z1) / H2 - (Z1 - Z0) / H1) / (H1 + H2);   // > 0 on a crest
			if (Curvature > 1.0e-3)
			{
				const float Speed = static_cast<float>(FMath::Sqrt(0.5 * 9.81 / Curvature));
				const int32 Bucket = FMath::RoundToInt(Road.Samples[i].S / 200.0f);
				for (int32 B = Bucket - 1; B <= Bucket + 1; ++B)
				{
					if (Limit.IsValidIndex(B))
					{
						Limit[B] = FMath::Min(Limit[B], Speed);
					}
				}
			}
		}
	}
	bCachesBuilt = true;
}

float URoamAutoDriveSubsystem::CrestLimitBetween(int32 RoadIndex, float S0Cm, float S1Cm) const
{
	if (!RoadCrestLimit.IsValidIndex(RoadIndex))
	{
		return 1.0e6f;
	}
	const TArray<float>& Limit = RoadCrestLimit[RoadIndex];
	const int32 B0 = FMath::Clamp(FMath::FloorToInt(FMath::Min(S0Cm, S1Cm) / 200.0f), 0, Limit.Num() - 1);
	const int32 B1 = FMath::Clamp(FMath::CeilToInt(FMath::Max(S0Cm, S1Cm) / 200.0f), 0, Limit.Num() - 1);
	float Result = 1.0e6f;
	for (int32 B = B0; B <= B1; ++B)
	{
		Result = FMath::Min(Result, Limit[B]);
	}
	return Result;
}

bool URoamAutoDriveSubsystem::PickNext(const FRoamPathCursor& From, FRoamPathCursor& Out) const
{
	if (!Network || !Network->Roads.IsValidIndex(From.RoadIndex))
	{
		return false;
	}
	const FRoamRoad& Road = Network->Roads[From.RoadIndex];
	const FName JunctionId = From.Dir > 0 ? Road.EndJunction : Road.StartJunction;
	if (JunctionId.IsNone())
	{
		return false;
	}
	const FRoamJunction* Junction = Network->FindJunction(JunctionId);
	if (!Junction)
	{
		return false;
	}
	const FName CurrentBase = RoadBaseName[From.RoadIndex];
	const int32 LoopIdx = RoadLoopIndex[From.RoadIndex];
	FName WantedBase = NAME_None;
	if (bFollowLoop && LoopIdx != INDEX_NONE)
	{
		WantedBase = FName(GLoopSequence[(LoopIdx + 1) % GNumLoopRoads]);
	}
	// direction of travel at the end of the current road
	FRoamRoadHit EndHit;
	Network->SamplePositionByIndex(From.RoadIndex, From.Dir > 0 ? Road.LengthCm : 0.0f, EndHit);
	const FVector TravelDir = EndHit.Tangent * static_cast<double>(From.Dir);

	float BestScore = -1.0e9f;
	bool bFound = false;
	for (const FRoamJunctionArm& Arm : Junction->Arms)
	{
		const int32 Index = Network->FindRoadIndex(Arm.RoadId);
		if (Index == INDEX_NONE)
		{
			continue;
		}
		if (Index == From.RoadIndex && Arm.bAtRoadStart == (From.Dir < 0))
		{
			continue; // the arm we arrived on
		}
		const FRoamRoad& Candidate = Network->Roads[Index];
		FRoamRoadHit ArmHit;
		Network->SamplePositionByIndex(Index, Arm.bAtRoadStart ? 0.0f : Candidate.LengthCm, ArmHit);
		const FVector Outgoing = ArmHit.Tangent * (Arm.bAtRoadStart ? 1.0 : -1.0);
		float Score = static_cast<float>(Outgoing | TravelDir);
		if (RoadBaseName[Index] == CurrentBase && (Outgoing | TravelDir) > -0.5)
		{
			Score += 10.0f;   // continuing along the same road (split edge, or a crossing road): always wins over the loop hand-over
		}
		else if (!WantedBase.IsNone() && RoadBaseName[Index] == WantedBase)
		{
			Score += 6.0f;
		}
		if (Score > BestScore)
		{
			BestScore = Score;
			Out.RoadIndex = Index;
			Out.S = Arm.bAtRoadStart ? 0.0f : Candidate.LengthCm;
			Out.Dir = Arm.bAtRoadStart ? 1 : -1;
			bFound = true;
		}
	}
	return bFound;
}

bool URoamAutoDriveSubsystem::Advance(FRoamPathCursor& Cur, float DistanceCm) const
{
	for (int32 Guard = 0; Guard < 24; ++Guard)
	{
		const FRoamRoad& Road = Network->Roads[Cur.RoadIndex];
		const float Remaining = Cur.Dir > 0 ? Road.LengthCm - Cur.S : Cur.S;
		if (DistanceCm <= Remaining)
		{
			Cur.S += static_cast<float>(Cur.Dir) * DistanceCm;
			return true;
		}
		DistanceCm -= Remaining;
		Cur.S = Cur.Dir > 0 ? Road.LengthCm : 0.0f;
		FRoamPathCursor Next;
		if (!PickNext(Cur, Next))
		{
			return false;
		}
		Cur = Next;
	}
	return false;
}

FVector URoamAutoDriveSubsystem::LanePosition(const FRoamPathCursor& Cur, FVector* OutTangent, float* OutSpeedLimitKmh, ERoamSurface* OutSurface) const
{
	FRoamRoadHit Hit;
	if (!Network->SamplePositionByIndex(Cur.RoadIndex, Cur.S, Hit))
	{
		return FVector::ZeroVector;
	}
	const FRoamRoad& Road = Network->Roads[Cur.RoadIndex];
	const int32 Available = FMath::Max(1, Cur.Dir > 0 ? Road.LanesForward : Road.LanesBackward);
	const int32 Lane = FMath::Min(LaneNumber, Available) * (Cur.Dir > 0 ? 1 : -1);
	if (OutTangent)
	{
		*OutTangent = Hit.Tangent * static_cast<double>(Cur.Dir);
	}
	if (OutSpeedLimitKmh)
	{
		*OutSpeedLimitKmh = Hit.SpeedLimitKmh;
	}
	if (OutSurface)
	{
		*OutSurface = Hit.Surface;
	}
	return Hit.Position + Hit.Right * static_cast<double>(Network->LaneOffsetCm(Road, Lane));
}

bool URoamAutoDriveSubsystem::AcquireCursor(const ARoamVehicle* Vehicle, FRoamPathCursor& OutCursor, FRoamRoadHit& OutHit) const
{
	FRoamRoadQuery Query;
	Query.Location = Vehicle->GetActorLocation();
	Query.Heading = Vehicle->GetActorForwardVector();
	Query.MaxDistanceCm = 300000.0f;
	if (!Network->FindNearest(Query, OutHit))
	{
		return false;
	}
	OutCursor.RoadIndex = OutHit.RoadIndex;
	OutCursor.S = OutHit.S;
	OutCursor.Dir = (OutHit.Tangent | Vehicle->GetActorForwardVector()) >= 0.0 ? 1 : -1;
	return true;
}

float URoamAutoDriveSubsystem::PlanSpeedMs(const ARoamVehicle* Vehicle, const FRoamPathCursor& From, float CruiseMs) const
{
	float LatG = 0.6f;
	float BrakeG = 0.8f;
	if (const URoamCarDefinition* Def = Vehicle->GetCarDefinition())
	{
		LatG = CachedLatG;
		BrakeG = FMath::Max(Def->Brakes.PeakDecelerationG, 0.5f);
	}
	const float LateralAccel = FMath::Clamp(0.45f * LatG, 0.28f, 0.70f) * 9.81f * GripFactor;
	const float BrakeAccel = FMath::Clamp(0.5f * BrakeG, 0.25f, 0.6f) * 9.81f;

	constexpr float StepCm = 1000.0f;
	const float LookCm = FMath::Clamp(100.0f * CruiseMs * CruiseMs / (2.0f * BrakeAccel) + 3000.0f, 6000.0f, 45000.0f);
	float Allowed = CruiseMs;
	FRoamPathCursor C = From;
	ERoamSurface Surface = ERoamSurface::Asphalt;
	FVector P0 = LanePosition(C, nullptr, nullptr, &Surface);
	if (!Advance(C, StepCm))
	{
		return FMath::Max(Allowed, 6.0f);
	}
	FVector P1 = LanePosition(C, nullptr, nullptr, &Surface);
	if (C.RoadIndex == From.RoadIndex)
	{
		Allowed = FMath::Min(Allowed, CrestLimitBetween(From.RoadIndex, From.S, C.S));
	}
	float PrevS = C.S;
	int32 PrevRoad = C.RoadIndex;
	for (float D = StepCm; D <= LookCm; D += StepCm)
	{
		PrevS = C.S;
		PrevRoad = C.RoadIndex;
		if (!Advance(C, StepCm))
		{
			break;
		}
		if (PrevRoad != C.RoadIndex)
		{
			PrevS = C.S;   // crossed a junction: only look at the new road's start
		}
		const FVector P2 = LanePosition(C, nullptr, nullptr, &Surface);
		const FVector A = P1 - P0;
		const FVector B = P2 - P1;
		const FVector AC = P2 - P0;
		{
			// vertical profile crest between the previous and this planning point (precomputed per road)
			const float CrestSpeed = CrestLimitBetween(C.RoadIndex, PrevS, C.S);
			if (CrestSpeed < 1.0e5f)
			{
				const float DistanceM = D * 0.01f;
				Allowed = FMath::Min(Allowed, FMath::Sqrt(CrestSpeed * CrestSpeed + 2.0f * BrakeAccel * DistanceM));
			}
		}
		const double Denominator = A.Size2D() * B.Size2D() * AC.Size2D();
		if (Denominator > 1.0)
		{
			const double Cross = FMath::Abs(A.X * B.Y - A.Y * B.X);
			const float KappaPerM = static_cast<float>(2.0 * Cross / Denominator) * 100.0f;
			if (KappaPerM > 1.0e-4f)
			{
				const float Grip = FMath::Max(Roam::SurfaceGripMultiplier(Surface, 0.0f), 0.4f);
				const float CornerSpeed = FMath::Sqrt(LateralAccel * Grip / KappaPerM);
				const float DistanceM = D * 0.01f;
				Allowed = FMath::Min(Allowed, FMath::Sqrt(CornerSpeed * CornerSpeed + 2.0f * BrakeAccel * DistanceM));
			}
		}
		P0 = P1;
		P1 = P2;
	}
	return FMath::Max(Allowed, 6.0f);
}

// ------------------------------------------------------------------------------------------------------------------
// Autopilot
// ------------------------------------------------------------------------------------------------------------------

void URoamAutoDriveSubsystem::ResetStats()
{
	Stats = FRoamAutoDriveStats();
	Stats.FrameMs.Reserve(120000);
	StuckTimer = OffRoadTimer = 0.0f;
	GraceTimer = 4.0f;
	StatusTimer = 0.0f;
	PlanTimer = 1.0f;
	SteerCmd = 0.0f;
	LastLoggedRoad = NAME_None;
	LastRealTime = 0.0;
}

bool URoamAutoDriveSubsystem::StartAutoDrive(float CruiseKmh, float InStopAfterKm, FString& OutMessage)
{
	ARoamVehicle* Vehicle = ARoamVehicle::GetPlayerVehicle(this);
	if (!Vehicle)
	{
		OutMessage = TEXT("no player vehicle");
		return false;
	}
	if (!EnsureNetwork())
	{
		OutMessage = TEXT("no road network (DA_RoadNetwork missing or empty)");
		return false;
	}
	FRoamRoadHit Hit;
	if (!AcquireCursor(Vehicle, Cursor, Hit))
	{
		OutMessage = TEXT("no road within 3 km of the car");
		return false;
	}
	bCursorValid = true;
	CruiseKmhSetting = CruiseKmh;
	StopAfterKm = InStopAfterKm;
	ResetStats();
	bActive = true;
	Vehicle->SetAIControlled(true);
	StartRealTime = FPlatformTime::Seconds();
	LastDistanceKm = Vehicle->GetTelemetry().DistanceKm;
	UE_LOG(LogRoamVehicle, Display, TEXT("ROAM_AUTODRIVE_START car=%s road=%s s=%.0f dir=%d cruise=%.0f stopAfterKm=%.1f dist_to_road_m=%.1f loop=%d lane=%d grip=%.2f"),
		*Vehicle->GetCarId().ToString(), *Network->Roads[Cursor.RoadIndex].RoadId.ToString(), Cursor.S, Cursor.Dir, CruiseKmh, StopAfterKm, Hit.DistanceCm * 0.01f, bFollowLoop ? 1 : 0, LaneNumber, GripFactor);
	OutMessage = FString::Printf(TEXT("autodrive on: road %s s=%.0f m dir %+d, cruise %s"), *Network->Roads[Cursor.RoadIndex].RoadId.ToString(), Cursor.S * 0.01f, Cursor.Dir,
		CruiseKmh > 0.0f ? *FString::Printf(TEXT("%.0f km/h"), CruiseKmh) : TEXT("speed limit"));
	return true;
}

void URoamAutoDriveSubsystem::RequestQuit()
{
	UE_LOG(LogRoamVehicle, Display, TEXT("ROAM_QUIT requested by the autopilot / car test"));
	if (APlayerController* PC = GetWorld() ? GetWorld()->GetFirstPlayerController() : nullptr)
	{
		PC->ConsoleCommand(TEXT("Quit"));
	}
}

bool URoamAutoDriveSubsystem::PlaceOnRoad(const FString& RoadId, float SMeters, FString& OutMessage)
{
	ARoamVehicle* Vehicle = ARoamVehicle::GetPlayerVehicle(this);
	if (!Vehicle || !EnsureNetwork())
	{
		OutMessage = TEXT("needs a player vehicle and a road network");
		return false;
	}
	int32 Index = Network->FindRoadIndex(FName(*RoadId));
	if (Index == INDEX_NONE)
	{
		// "LOOP_COAST" without the split suffix: the first edge (#0)
		for (int32 i = 0; i < Network->Roads.Num() && Index == INDEX_NONE; ++i)
		{
			if (RoadBaseName[i] == FName(*RoadId) && Network->Roads[i].RoadId.ToString().EndsWith(TEXT("#0")))
			{
				Index = i;
			}
		}
	}
	if (Index == INDEX_NONE)
	{
		OutMessage = FString::Printf(TEXT("unknown road '%s'"), *RoadId);
		return false;
	}
	FRoamPathCursor Place;
	Place.RoadIndex = Index;
	Place.Dir = 1;
	Place.S = FMath::Clamp(SMeters * 100.0f, 0.0f, Network->Roads[Index].LengthCm - 100.0f);
	FVector Tangent = FVector::ForwardVector;
	const FVector Position = LanePosition(Place, &Tangent);
	Vehicle->TeleportVehicle(FTransform(FRotator(0.0f, static_cast<float>(Tangent.Rotation().Yaw), 0.0f), Position + FVector(0.0, 0.0, 60.0)), false);
	OutMessage = FString::Printf(TEXT("placed on %s at s=%.0f m"), *Network->Roads[Index].RoadId.ToString(), Place.S * 0.01f);
	return true;
}

void URoamAutoDriveSubsystem::StopAutoDrive(const TCHAR* Reason)
{
	if (!bActive)
	{
		return;
	}
	bActive = false;
	LogEnd(Reason);
	if (bQuitWhenDone && CarTest.Phase == ECarTestPhase::Idle)
	{
		RequestQuit();
	}
	if (ARoamVehicle* Vehicle = ARoamVehicle::GetPlayerVehicle(this))
	{
		Vehicle->SetThrottle(0.0f);
		Vehicle->SetBrake(0.3f);
		Vehicle->SetSteer(0.0f);
		if (CarTest.Phase == ECarTestPhase::Idle)
		{
			Vehicle->SetAIControlled(false);
		}
	}
}

void URoamAutoDriveSubsystem::RecordFrame(float RealDtSeconds)
{
	const float Ms = RealDtSeconds * 1000.0f;
	Stats.FrameMs.Add(Ms);
	Stats.MaxFrameMs = FMath::Max(Stats.MaxFrameMs, Ms);
	if (Ms > 50.0f) { ++Stats.Hitches50; }
	if (Ms > 100.0f) { ++Stats.Hitches100; }
	if (Ms > 250.0f) { ++Stats.Hitches250; }
}

FString URoamAutoDriveSubsystem::DescribeStatus() const
{
	const double AvgKmh = Stats.GameSeconds > 0.5 ? Stats.DistanceM / Stats.GameSeconds * 3.6 : 0.0;
	const FString RoadName = (bCursorValid && Network && Network->Roads.IsValidIndex(Cursor.RoadIndex)) ? Network->Roads[Cursor.RoadIndex].RoadId.ToString() : TEXT("-");
	return FString::Printf(TEXT("autodrive %s: road %s s=%.0f dir %+d | %.2f km in %.0f s (avg %.0f, max %.0f km/h) | zMargin min %.0f max %.0f cm | stuck %d offroad %d fall %d lost %d laps %d | hitches>50ms %d >100ms %d, max frame %.0f ms | planned %.0f km/h"),
		bActive ? TEXT("ON") : TEXT("off"), *RoadName, Cursor.S * 0.01f, Cursor.Dir, Stats.DistanceM * 0.001, Stats.GameSeconds, AvgKmh, Stats.MaxSpeedKmh,
		Stats.MinZMarginCm > 1.0e8f ? 0.0f : Stats.MinZMarginCm, Stats.MaxZMarginCm < -1.0e8f ? 0.0f : Stats.MaxZMarginCm,
		Stats.StuckEvents, Stats.OffRoadEvents, Stats.FallEvents, Stats.LostEvents, Stats.Laps, Stats.Hitches50, Stats.Hitches100, Stats.MaxFrameMs, PlannedSpeedMs * 3.6f);
}

void URoamAutoDriveSubsystem::LogEnd(const TCHAR* Reason) const
{
	TArray<float> Sorted = Stats.FrameMs;
	Sorted.Sort();
	const int32 N = Sorted.Num();
	double Sum = 0.0;
	for (float Ms : Sorted) { Sum += Ms; }
	const float AvgMs = N > 0 ? static_cast<float>(Sum / N) : 0.0f;
	const float P50 = N > 0 ? Sorted[N / 2] : 0.0f;
	const float P99 = N > 0 ? Sorted[FMath::Min(N - 1, static_cast<int32>(N * 0.99))] : 0.0f;
	const double AvgKmh = Stats.GameSeconds > 0.5 ? Stats.DistanceM / Stats.GameSeconds * 3.6 : 0.0;
	UE_LOG(LogRoamVehicle, Display, TEXT("ROAM_AUTODRIVE_END reason=%s dist_km=%.3f game_s=%.1f avg_kmh=%.1f max_kmh=%.1f zmargin_min_cm=%.0f zmargin_max_cm=%.0f lat_err_max_cm=%.0f stuck=%d offroad=%d fall=%d lost=%d laps=%d bumps=%d"),
		Reason, Stats.DistanceM * 0.001, Stats.GameSeconds, AvgKmh, Stats.MaxSpeedKmh, Stats.MinZMarginCm > 1.0e8f ? 0.0f : Stats.MinZMarginCm, Stats.MaxZMarginCm < -1.0e8f ? 0.0f : Stats.MaxZMarginCm,
		Stats.MaxLateralErrCm, Stats.StuckEvents, Stats.OffRoadEvents, Stats.FallEvents, Stats.LostEvents, Stats.Laps, Stats.Bumps);
	UE_LOG(LogRoamVehicle, Display, TEXT("ROAM_AUTODRIVE_DYN roll_max=%.1f pitch_max=%.1f yawrate_max=%.1f slip_max=%.1f latg_max=%.2f vertg_min=%.2f vertg_max=%.2f"),
		Stats.MaxRollDeg, Stats.MaxPitchDeg, Stats.MaxYawRateDeg, Stats.MaxSlipDeg, Stats.MaxLatG, Stats.MinVertG > 1.0e8f ? 0.0f : Stats.MinVertG, Stats.MaxVertG < -1.0e8f ? 0.0f : Stats.MaxVertG);
	UE_LOG(LogRoamVehicle, Display, TEXT("ROAM_AUTODRIVE_FRAMES frames=%d avg_ms=%.1f p50_ms=%.1f p99_ms=%.1f max_ms=%.1f hitch50=%d hitch100=%d hitch250=%d"),
		N, AvgMs, P50, P99, Stats.MaxFrameMs, Stats.Hitches50, Stats.Hitches100, Stats.Hitches250);
}

void URoamAutoDriveSubsystem::Recover(ARoamVehicle* Vehicle, const TCHAR* Why, float AheadCm)
{
	FRoamPathCursor Target = Cursor;
	Advance(Target, AheadCm);
	FVector Tangent = FVector::ForwardVector;
	const FVector Position = LanePosition(Target, &Tangent);
	const FRotator Rotation(0.0f, static_cast<float>(Tangent.Rotation().Yaw), 0.0f);
	UE_LOG(LogRoamVehicle, Display, TEXT("ROAM_AUTODRIVE_RECOVER why=%s road=%s s=%.0f -> road=%s s=%.0f at (%.0f, %.0f, %.0f) dist_km=%.3f"), Why, *Network->Roads[Cursor.RoadIndex].RoadId.ToString(), Cursor.S,
		*Network->Roads[Target.RoadIndex].RoadId.ToString(), Target.S, Position.X, Position.Y, Position.Z, Stats.DistanceM * 0.001);
	Vehicle->TeleportVehicle(FTransform(Rotation, Position + FVector(0.0, 0.0, 45.0)), false);
	Cursor = Target;
	GraceTimer = 3.0f;
	StuckTimer = 0.0f;
	OffRoadTimer = 0.0f;
	SteerCmd = 0.0f;
	PlanTimer = 1.0f;
}

void URoamAutoDriveSubsystem::DriveTick(ARoamVehicle* Vehicle, float DeltaTime)
{
	if (!EnsureNetwork())
	{
		StopAutoDrive(TEXT("no_network"));
		return;
	}
	const FRoamVehicleTelemetry& T = Vehicle->GetTelemetry();
	const URoamCarDefinition* Def = Vehicle->GetCarDefinition();
	if (Vehicle->GetCarId() != LastCarId)
	{
		LastCarId = Vehicle->GetCarId();
		CachedLatG = 0.6f;
		if (Def)
		{
			CachedLatG = FMath::Max(Def->ComputePerformance(FRoamPerformanceRules()).LateralG, 0.4f);
		}
		LastDistanceKm = T.DistanceKm;
		GraceTimer = 3.0f;
	}
	if (!Vehicle->IsAIControlled())
	{
		Vehicle->SetAIControlled(true);
	}

	const FVector Location = Vehicle->GetActorLocation();
	const FVector Forward = Vehicle->GetActorForwardVector();

	// ---- project the car on the road, switch roads at junctions ---------------------------------------------------------------------
	FRoamRoadHit HitA;
	bool bFound = bCursorValid && Network->Roads.IsValidIndex(Cursor.RoadIndex) && Network->FindNearestOnRoad(Cursor.RoadIndex, Location, Cursor.S, 6000.0f, HitA);
	if (!bFound || HitA.DistanceCm > 8000.0f)
	{
		++Stats.LostEvents;
		FRoamPathCursor Fresh;
		FRoamRoadHit FreshHit;
		if (!AcquireCursor(Vehicle, Fresh, FreshHit))
		{
			StopAutoDrive(TEXT("lost_no_road"));
			return;
		}
		UE_LOG(LogRoamVehicle, Display, TEXT("ROAM_AUTODRIVE_LOST was road=%s now road=%s s=%.0f dist_m=%.0f"), bCursorValid ? *Network->Roads[Cursor.RoadIndex].RoadId.ToString() : TEXT("-"),
			*Network->Roads[Fresh.RoadIndex].RoadId.ToString(), Fresh.S, FreshHit.DistanceCm * 0.01f);
		Cursor = Fresh;
		HitA = FreshHit;
		bCursorValid = true;
	}
	{
		const FRoamRoad& Road = Network->Roads[Cursor.RoadIndex];
		const float ToEnd = Cursor.Dir > 0 ? Road.LengthCm - HitA.S : HitA.S;
		if (ToEnd < 4000.0f)
		{
			FRoamPathCursor AtEnd = Cursor;
			AtEnd.S = Cursor.Dir > 0 ? Road.LengthCm : 0.0f;
			FRoamPathCursor Next;
			if (PickNext(AtEnd, Next))
			{
				FRoamRoadHit HitB;
				if (Network->FindNearestOnRoad(Next.RoadIndex, Location, Next.S, 5000.0f, HitB) && (HitB.DistanceCm < HitA.DistanceCm - 30.0f || ToEnd < 100.0f))
				{
					Cursor = Next;
					HitA = HitB;
				}
			}
		}
		Cursor.S = HitA.S;
	}
	{
		const int32 LoopIdx = RoadLoopIndex[Cursor.RoadIndex];
		if (LoopIdx == GNumLoopRoads - 1)
		{
			bSeenLastLoopRoad = true;
		}
		else if (LoopIdx == 0 && bSeenLastLoopRoad)
		{
			bSeenLastLoopRoad = false;
			++Stats.Laps;
			UE_LOG(LogRoamVehicle, Display, TEXT("ROAM_AUTODRIVE_LAP lap=%d dist_km=%.3f game_s=%.1f"), Stats.Laps, Stats.DistanceM * 0.001, Stats.GameSeconds);
		}
	}
	if (RoadBaseName[Cursor.RoadIndex] != LastLoggedRoad)
	{
		LastLoggedRoad = RoadBaseName[Cursor.RoadIndex];
		UE_LOG(LogRoamVehicle, Display, TEXT("ROAM_AUTODRIVE_ROAD road=%s dir=%d dist_km=%.3f game_s=%.1f speed=%.0f"), *Network->Roads[Cursor.RoadIndex].RoadId.ToString(), Cursor.Dir, Stats.DistanceM * 0.001, Stats.GameSeconds, T.SpeedKmh);
	}

	// ---- statistics -----------------------------------------------------------------------------------------------------------------------
	const FRoamRoad& CurrentRoad = Network->Roads[Cursor.RoadIndex];
	const int32 LaneAvailable = FMath::Max(1, Cursor.Dir > 0 ? CurrentRoad.LanesForward : CurrentRoad.LanesBackward);
	const float LaneOffset = Network->LaneOffsetCm(CurrentRoad, FMath::Min(LaneNumber, LaneAvailable) * (Cursor.Dir > 0 ? 1 : -1));
	const float LateralErr = HitA.LateralCm - LaneOffset;
	const float ZMargin = static_cast<float>(Location.Z - HitA.Position.Z);
	Stats.GameSeconds += DeltaTime;
	Stats.DistanceM += T.SpeedMs * DeltaTime;
	Stats.MaxSpeedKmh = FMath::Max(Stats.MaxSpeedKmh, T.SpeedKmh);
	Stats.MinZMarginCm = FMath::Min(Stats.MinZMarginCm, ZMargin);
	Stats.MaxZMarginCm = FMath::Max(Stats.MaxZMarginCm, ZMargin);
	Stats.MaxLateralErrCm = FMath::Max(Stats.MaxLateralErrCm, FMath::Abs(LateralErr));
	Stats.MaxRollDeg = FMath::Max(Stats.MaxRollDeg, FMath::Abs(T.RollDeg));
	Stats.MaxPitchDeg = FMath::Max(Stats.MaxPitchDeg, FMath::Abs(T.PitchDeg));
	Stats.MaxYawRateDeg = FMath::Max(Stats.MaxYawRateDeg, FMath::Abs(T.YawRateDeg));
	Stats.MaxSlipDeg = FMath::Max(Stats.MaxSlipDeg, FMath::Abs(T.BodySlipAngleDeg));
	Stats.MaxLatG = FMath::Max(Stats.MaxLatG, FMath::Abs(T.LatG));
	Stats.MinVertG = FMath::Min(Stats.MinVertG, T.VertG);
	Stats.MaxVertG = FMath::Max(Stats.MaxVertG, T.VertG);
	GraceTimer = FMath::Max(0.0f, GraceTimer - DeltaTime);
	BumpCooldown = FMath::Max(0.0f, BumpCooldown - DeltaTime);
	if (BumpCooldown <= 0.0f && (T.VertG > 2.2f || ZMargin > 60.0f || T.NumWheelsOnGround == 0) && T.SpeedKmh > 20.0f)
	{
		// road defects (steps at chunk seams, culverts, junction pads) show up as vertical jolts / launches: log where
		++Stats.Bumps;
		BumpCooldown = 1.5f;
		UE_LOG(LogRoamVehicle, Display, TEXT("ROAM_AUTODRIVE_BUMP road=%s s=%.0f dist_km=%.3f v=%.0f vertG=%.2f zMargin_cm=%.0f wheelsOnGround=%d pos=(%.0f %.0f %.0f)"), *Network->Roads[Cursor.RoadIndex].RoadId.ToString(), Cursor.S * 0.01f,
			Stats.DistanceM * 0.001, T.SpeedKmh, T.VertG, ZMargin, T.NumWheelsOnGround, Location.X, Location.Y, Location.Z);
	}

	// ---- speed plan (10 Hz) -------------------------------------------------------------------------------------------------------------------
	const float LimitMs = HitA.SpeedLimitKmh / 3.6f;
	const float Over = OverspeedFactor > 0.0f ? OverspeedFactor : (CruiseKmhSetting > 0.0f ? 1.3f : 1.0f);
	float CruiseMs = FMath::Max(LimitMs * Over, 8.0f);
	if (CruiseKmhSetting > 0.0f)
	{
		CruiseMs = FMath::Min(CruiseMs, CruiseKmhSetting / 3.6f);
	}
	PlanTimer += DeltaTime;
	if (PlanTimer >= 0.1f)
	{
		PlanTimer = 0.0f;
		PlannedSpeedMs = PlanSpeedMs(Vehicle, Cursor, CruiseMs);
	}

	// ---- pure-pursuit steering ----------------------------------------------------------------------------------------------------------------
	const float LookAheadCm = FMath::Clamp(T.SpeedMs * 70.0f + 350.0f, 550.0f, 8000.0f);
	FRoamPathCursor TargetCursor = Cursor;
	Advance(TargetCursor, LookAheadCm);
	const FVector TargetPos = LanePosition(TargetCursor);
	FVector ToTarget = TargetPos - Location;
	ToTarget.Z = 0.0;
	const float DistanceToTarget = static_cast<float>(ToTarget.Size());
	FVector Forward2D = Forward;
	Forward2D.Z = 0.0;
	Forward2D = Forward2D.GetSafeNormal();
	const FVector ToTargetDir = ToTarget.GetSafeNormal();
	const float SinAlpha = static_cast<float>(Forward2D.X * ToTargetDir.Y - Forward2D.Y * ToTargetDir.X);   // > 0: target on the right
	const float CosAlpha = static_cast<float>(Forward2D | ToTargetDir);
	const float Alpha = FMath::Atan2(SinAlpha, CosAlpha);
	const float WheelbaseCm = Def ? Def->Geometry.WheelbaseCm : 260.0f;
	const float DeltaDeg = FMath::RadiansToDegrees(FMath::Atan2(2.0f * WheelbaseCm * FMath::Sin(Alpha), FMath::Max(DistanceToTarget, 200.0f)));
	const float MaxSteerDeg = Def ? Def->Steering.MaxSteerAngleDeg : 34.0f;
	const float Lock = Def ? FMath::Max(Def->Steering.GetLockFraction(T.SpeedKmh), 0.05f) : 1.0f;
	const float SteerRaw = FMath::Clamp(DeltaDeg / (MaxSteerDeg * Lock), -1.0f, 1.0f);
	SteerCmd = FMath::FInterpTo(SteerCmd, SteerRaw, DeltaTime, 25.0f);

	// ---- car following: sweep ahead for traffic (object channel Roam_Traffic) and keep a time gap --------------------------------------------------
	float EffectivePlanMs = PlannedSpeedMs;
	bool bFollowingStopped = false;
	{
		const float SweepCm = FMath::Clamp(T.SpeedMs * 250.0f + 3000.0f, 3000.0f, 20000.0f);
		FVector SweepDir = (FMath::Abs(SinAlpha) < 0.45f) ? ToTargetDir : Forward2D;
		SweepDir.Z = 0.0;
		SweepDir = SweepDir.GetSafeNormal();
		const FVector Start = Location + SweepDir * 230.0 + FVector(0.0, 0.0, 70.0);
		FHitResult LeadHit;
		FCollisionQueryParams LeadParams(SCENE_QUERY_STAT(RoamAutoDriveLead), false, Vehicle);
		const FCollisionObjectQueryParams LeadObjects(RoamCollision::ObjectTraffic);
		if (GetWorld() && GetWorld()->SweepSingleByObjectType(LeadHit, Start, Start + SweepDir * SweepCm, SweepDir.Rotation().Quaternion(), LeadObjects, FCollisionShape::MakeBox(FVector(20.0, 105.0, 60.0)), LeadParams) && LeadHit.GetActor())
		{
			AActor* Lead = LeadHit.GetActor();
			const double Now = GetWorld()->GetTimeSeconds();
			if (LeadActor.Get() != Lead)
			{
				LeadActor = Lead;
				LeadSpeedMs = 0.0f;
				LeadLastPos = Lead->GetActorLocation();
				LeadLastTime = Now;
			}
			else if (Now - LeadLastTime > 0.15)
			{
				const FVector Pos = Lead->GetActorLocation();
				LeadSpeedMs = FMath::Max(0.0f, static_cast<float>(((Pos - LeadLastPos) | SweepDir) / (100.0 * (Now - LeadLastTime))));
				LeadLastPos = Pos;
				LeadLastTime = Now;
			}
			const float GapM = LeadHit.Distance * 0.01f;
			const float DesiredGapM = 6.0f + 1.3f * T.SpeedMs;
			const float FollowMs = GapM < 3.5f ? 0.0f : FMath::Max(0.0f, LeadSpeedMs + 0.35f * (GapM - DesiredGapM));
			EffectivePlanMs = FMath::Min(EffectivePlanMs, FollowMs);
			bFollowingStopped = FollowMs < 1.0f && LeadSpeedMs < 1.0f;
		}
		else
		{
			LeadActor.Reset();
		}
	}
	FollowBlockTimer = (bFollowingStopped && T.SpeedMs < 0.9f) ? FollowBlockTimer + DeltaTime : 0.0f;

	// ---- pedals ---------------------------------------------------------------------------------------------------------------------------------------
	const float Error = EffectivePlanMs - T.SpeedMs;
	float Throttle = 0.0f;
	float Brake = 0.0f;
	if (Error > 0.0f)
	{
		Throttle = FMath::Clamp(0.15f + Error * 0.45f, 0.0f, 1.0f);
	}
	else if (Error < -0.7f)
	{
		Brake = FMath::Clamp((-Error - 0.7f) * 0.18f, 0.0f, 1.0f);
	}
	else
	{
		Throttle = FMath::Clamp(0.12f + 0.2f * (Error + 0.7f), 0.0f, 0.3f);   // roll on a light throttle inside the dead band
	}
	Vehicle->SetThrottle(Throttle);
	Vehicle->SetBrake(Brake);
	Vehicle->SetSteer(SteerCmd);
	Vehicle->SetHandbrake(0.0f);

	// ---- event detection ----------------------------------------------------------------------------------------------------------------------------
	if (GraceTimer <= 0.0f)
	{
		StuckTimer = (T.SpeedMs < 0.9f && PlannedSpeedMs > 4.0f) ? StuckTimer + DeltaTime : 0.0f;
		const bool bNearJunction = (HitA.Flags & static_cast<uint8>(ERoamRoadSection::Junction)) != 0 || (Cursor.Dir > 0 ? CurrentRoad.LengthCm - Cursor.S : Cursor.S) < 3000.0f || (Cursor.Dir > 0 ? Cursor.S : CurrentRoad.LengthCm - Cursor.S) < 3000.0f;
		const bool bOffRoad = !bNearJunction && FMath::Abs(HitA.LateralCm) > HitA.WidthCm * 0.5f + 250.0f;
		OffRoadTimer = bOffRoad ? OffRoadTimer + DeltaTime : 0.0f;
		if (ZMargin < -250.0f)
		{
			++Stats.FallEvents;
			Recover(Vehicle, TEXT("fell_below_road"), 0.0f);
		}
		else if (FollowBlockTimer > 10.0f)
		{
			++Stats.StuckEvents;
			FollowBlockTimer = 0.0f;
			Recover(Vehicle, TEXT("blocked_by_traffic"), 3000.0f);
		}
		else if (StuckTimer > 4.0f)
		{
			++Stats.StuckEvents;
			Recover(Vehicle, TEXT("stuck"), 1500.0f);
		}
		else if (OffRoadTimer > 2.5f)
		{
			++Stats.OffRoadEvents;
			Recover(Vehicle, TEXT("off_road"), 800.0f);
		}
	}

	StatusTimer += DeltaTime;
	if (StatusTimer >= 5.0f)
	{
		StatusTimer = 0.0f;
		UE_LOG(LogRoamVehicle, Display, TEXT("ROAM_AUTODRIVE_STATUS t=%.0f road=%s s=%.0f dist_km=%.2f v=%.0f plan=%.0f lat_cm=%.0f z_cm=%.0f gear=%d steer=%.2f maxframe_ms=%.0f stuck=%d off=%d fall=%d"), Stats.GameSeconds, *Network->Roads[Cursor.RoadIndex].RoadId.ToString(),
			Cursor.S * 0.01f, Stats.DistanceM * 0.001, T.SpeedKmh, PlannedSpeedMs * 3.6f, LateralErr, ZMargin, T.Gear, SteerCmd, Stats.MaxFrameMs, Stats.StuckEvents, Stats.OffRoadEvents, Stats.FallEvents);
	}
	if (StopAfterKm > 0.0f && Stats.DistanceM * 0.001 >= StopAfterKm)
	{
		StopAutoDrive(TEXT("distance_reached"));
	}
}

void URoamAutoDriveSubsystem::Tick(float DeltaTime)
{
	if (DeltaTime <= 0.0f)
	{
		return;
	}
	if (CarTest.Phase != ECarTestPhase::Idle)
	{
		TickCarTest(DeltaTime);
	}
	if (!bActive)
	{
		return;
	}
	ARoamVehicle* Vehicle = ARoamVehicle::GetPlayerVehicle(this);
	if (!Vehicle)
	{
		return;
	}
	const double Now = FPlatformTime::Seconds();
	if (LastRealTime > 0.0)
	{
		RecordFrame(static_cast<float>(Now - LastRealTime));
	}
	LastRealTime = Now;
	DriveTick(Vehicle, DeltaTime);
}

// ------------------------------------------------------------------------------------------------------------------
// Car test
// ------------------------------------------------------------------------------------------------------------------

void URoamAutoDriveSubsystem::TakeShot(const FString& Tag)
{
	if (APlayerController* PC = GetWorld() ? GetWorld()->GetFirstPlayerController() : nullptr)
	{
		PC->ConsoleCommand(TEXT("HighResShot 1280x720"));
	}
	UE_LOG(LogRoamVehicle, Display, TEXT("ROAM_CARTEST_SHOT %s"), *Tag);
}

bool URoamAutoDriveSubsystem::StartCarTest(int32 First, int32 Last, float DriveSeconds, bool bCameraShots, FString& OutMessage)
{
	ARoamVehicle* Vehicle = ARoamVehicle::GetPlayerVehicle(this);
	URoamGameInstance* GameInstance = URoamGameInstance::Get(this);
	URoamCarCatalog* Catalog = GameInstance ? GameInstance->GetCarCatalog() : nullptr;
	if (!Vehicle || !Catalog || Catalog->GetNumCars() == 0)
	{
		OutMessage = TEXT("needs a player vehicle and a car catalog");
		return false;
	}
	StopAutoDrive(TEXT("cartest"));
	const int32 Count = Catalog->GetNumCars();
	CarTest = FCarTestState();
	CarTest.First = FMath::Clamp(First, 1, Count);
	CarTest.Last = FMath::Clamp(Last, CarTest.First, Count);
	CarTest.Current = CarTest.First;
	CarTest.DriveSeconds = FMath::Clamp(DriveSeconds, 2.0f, 60.0f);
	CarTest.bCams = bCameraShots;
	FTransform Start = Vehicle->GetActorTransform();
	Start.SetRotation(FQuat(FRotator(0.0f, Start.Rotator().Yaw, 0.0f)));
	Start.SetScale3D(FVector::OneVector);
	Start.AddToTranslation(FVector(0.0, 0.0, 30.0));
	if (EnsureNetwork())
	{
		// start in the middle of a lane of the road under the car (highway centrelines carry the median barrier)
		FRoamPathCursor LaneCursor;
		FRoamRoadHit LaneHit;
		if (AcquireCursor(Vehicle, LaneCursor, LaneHit))
		{
			FVector Tangent = FVector::ForwardVector;
			const FVector LanePos = LanePosition(LaneCursor, &Tangent);
			Start = FTransform(FRotator(0.0f, static_cast<float>(Tangent.Rotation().Yaw), 0.0f), LanePos + FVector(0.0, 0.0, 40.0));
		}
	}
	CarTest.Start = Start;
	CarTest.Phase = ECarTestPhase::Spawn;
	UE_LOG(LogRoamVehicle, Display, TEXT("ROAM_CARTEST_BEGIN cars=%d..%d drive_s=%.1f cams=%d at (%.0f, %.0f, %.0f) yaw=%.1f"), CarTest.First, CarTest.Last, CarTest.DriveSeconds, bCameraShots ? 1 : 0,
		Start.GetLocation().X, Start.GetLocation().Y, Start.GetLocation().Z, Start.Rotator().Yaw);
	OutMessage = FString::Printf(TEXT("car test started: cars %d..%d, %.0f s drive each (watch the log for ROAM_CARTEST_*)"), CarTest.First, CarTest.Last, CarTest.DriveSeconds);
	return true;
}

void URoamAutoDriveSubsystem::CarTestEnd(const TCHAR* Reason)
{
	UE_LOG(LogRoamVehicle, Display, TEXT("ROAM_CARTEST_END reason=%s"), Reason);
	CarTest.Phase = ECarTestPhase::Idle;
	if (bQuitWhenDone)
	{
		RequestQuit();
	}
	if (ARoamVehicle* Vehicle = ARoamVehicle::GetPlayerVehicle(this))
	{
		Vehicle->SetThrottle(0.0f);
		Vehicle->SetBrake(0.0f);
		Vehicle->SetSteer(0.0f);
		Vehicle->SetAIControlled(false);
	}
}

void URoamAutoDriveSubsystem::CarTestBeginCar()
{
	ARoamGameMode* GameMode = ARoamGameMode::Get(this);
	URoamGameInstance* GameInstance = URoamGameInstance::Get(this);
	URoamCarCatalog* Catalog = GameInstance ? GameInstance->GetCarCatalog() : nullptr;
	URoamCarDefinition* Def = Catalog ? Catalog->GetCarByIndex(CarTest.Current - 1) : nullptr;
	if (!GameMode || !Def)
	{
		UE_LOG(LogRoamVehicle, Warning, TEXT("ROAM_CARTEST_FAIL n=%d: no game mode or the catalog entry is missing"), CarTest.Current);
		CarTestEnd(TEXT("missing_car"));
		return;
	}
	// fresh measurement windows, same configuration
	FCarTestState Fresh;
	Fresh.First = CarTest.First;
	Fresh.Last = CarTest.Last;
	Fresh.Current = CarTest.Current;
	Fresh.DriveSeconds = CarTest.DriveSeconds;
	Fresh.bCams = CarTest.bCams;
	Fresh.Start = CarTest.Start;
	Fresh.CarId = Def->CarId;
	Fresh.Phase = ECarTestPhase::Settle;
	CarTest = Fresh;
	ARoamVehicle* Vehicle = GameMode->SpawnPlayerCar(Def->CarId, CarTest.Start);
	if (!Vehicle)
	{
		UE_LOG(LogRoamVehicle, Warning, TEXT("ROAM_CARTEST_FAIL n=%d car=%s: spawn failed"), CarTest.Current, *Def->CarId.ToString());
		CarTestEnd(TEXT("spawn_failed"));
		return;
	}
	Vehicle->SetAIControlled(true);
	Vehicle->SetThrottle(0.0f);
	Vehicle->SetBrake(0.0f);
	Vehicle->SetSteer(0.0f);
	UE_LOG(LogRoamVehicle, Display, TEXT("ROAM_CARTEST_CAR n=%d car=%s mass=%.0f"), CarTest.Current, *Def->CarId.ToString(), Def->MassKg);
}

void URoamAutoDriveSubsystem::CarTestLogRest(ARoamVehicle* Vehicle)
{
	UWorld* World = GetWorld();
	const URoamCarDefinition* Def = Vehicle->GetCarDefinition();
	const FRoamVehicleTelemetry& T = Vehicle->GetTelemetry();
	const FTransform Xf = Vehicle->GetActorTransform();
	float GroundZ = 0.0f;
	FVector GroundNormal = FVector::UpVector;
	const bool bGround = GroundBelow(World, Vehicle, Vehicle->GetActorLocation(), GroundZ, &GroundNormal);
	const float OriginAbove = bGround ? static_cast<float>(Vehicle->GetActorLocation().Z) - GroundZ : -999.0f;
	const float Tilt = FMath::RadiansToDegrees(FMath::Acos(FMath::Clamp(static_cast<float>(Vehicle->GetActorUpVector() | GroundNormal), -1.0f, 1.0f)));

	float HubAbove[4] = { 0, 0, 0, 0 };
	float Radius[4] = { 0, 0, 0, 0 };
	float TyreGap[4] = { 0, 0, 0, 0 };
	float XyErr[4] = { 0, 0, 0, 0 };
	float BoundsRadius[4] = { 0, 0, 0, 0 };
	bool bWheelsOk = true;
	for (int32 i = 0; i < Roam::NumWheels; ++i)
	{
		UStaticMeshComponent* Wheel = Vehicle->WheelMeshes.IsValidIndex(i) ? Vehicle->WheelMeshes[i].Get() : nullptr;
		if (!Wheel || !Def)
		{
			bWheelsOk = false;
			continue;
		}
		const FVector Hub = Wheel->GetComponentLocation();
		float Gz = 0.0f;
		GroundBelow(World, Vehicle, Hub, Gz);
		Radius[i] = Def->Geometry.GetWheel(i).RadiusCm;
		HubAbove[i] = static_cast<float>(Hub.Z) - Gz;
		const FBoxSphereBounds Bounds = Wheel->Bounds;
		TyreGap[i] = static_cast<float>(Bounds.Origin.Z - Bounds.BoxExtent.Z) - Gz;
		BoundsRadius[i] = static_cast<float>(Bounds.BoxExtent.Z);
		const FVector Expected = Xf.TransformPosition(Def->Geometry.GetWheel(i).CenterCm);
		XyErr[i] = static_cast<float>(FVector::Dist2D(Hub, Expected));
		if (FMath::Abs(HubAbove[i] - Radius[i]) > 3.0f)
		{
			bWheelsOk = false;
		}
	}
	float BodyGap = -999.0f;
	if (Vehicle->Body && Vehicle->Body->GetStaticMesh() && bGround)
	{
		const FBoxSphereBounds B = Vehicle->Body->Bounds;
		BodyGap = static_cast<float>(B.Origin.Z - B.BoxExtent.Z) - GroundZ;
	}
	const float Travel[4] = { T.WheelTravelCm[0], T.WheelTravelCm[1], T.WheelTravelCm[2], T.WheelTravelCm[3] };
	const float Load[4] = { T.WheelLoadN[0], T.WheelLoadN[1], T.WheelLoadN[2], T.WheelLoadN[3] };
	const URoamVehicleMovement* Movement = Vehicle->VehicleMovement;
	const bool bPhysics = Movement && Movement->IsPhysicsReady();
	UE_LOG(LogRoamVehicle, Display, TEXT("ROAM_CARTEST_REST n=%d car=%s phys=%d wheelsOnGround=%d originAboveGround_cm=%.1f tilt_deg=%.2f pitch=%.2f roll=%.2f hubAbove_cm=%s wheelRadius_cm=%s tyreBottomGap_cm=%s meshRadius_cm=%s wheelXYerr_cm=%s travel_cm=%s load_N=%s bodyUnderside_gap_cm=%.1f"),
		CarTest.Current, *CarTest.CarId.ToString(), bPhysics ? 1 : 0, T.NumWheelsOnGround, OriginAbove, Tilt, T.PitchDeg, T.RollDeg, *FloatArray4(HubAbove), *FloatArray4(Radius), *FloatArray4(TyreGap),
		*FloatArray4(BoundsRadius), *FloatArray4(XyErr), *FloatArray4(Travel), *FloatArray4(Load, true), BodyGap);
	UE_LOG(LogRoamVehicle, Display, TEXT("ROAM_CARTEST_JITTER n=%d car=%s speedMax_kmh=%.2f vertG=[%.3f %.3f] tiltMax_deg=%.2f zRange_cm=%.2f"), CarTest.Current, *CarTest.CarId.ToString(), CarTest.RestMaxSpeedKmh,
		CarTest.RestMinVertG, CarTest.RestMaxVertG, CarTest.RestMaxTiltDeg, CarTest.RestMaxZ - CarTest.RestMinZ);
	UE_LOG(LogRoamVehicle, Display, TEXT("ROAM_CARTEST_MATS n=%d car=%s %s"), CarTest.Current, *CarTest.CarId.ToString(), Vehicle->Visuals ? *Vehicle->Visuals->DescribeMaterials() : TEXT("no visuals"));
	if (Vehicle->Visuals)
	{
		const FLinearColor P = Vehicle->Visuals->ReadPrimaryColor(false);
		const FLinearColor S = Vehicle->Visuals->ReadPrimaryColor(true);
		UE_LOG(LogRoamVehicle, Display, TEXT("ROAM_CARTEST_PAINT n=%d car=%s paintPrimary=(%.2f %.2f %.2f) paint2Primary=(%.2f %.2f %.2f) vehiclePaint=(%.2f %.2f %.2f)/(%.2f %.2f %.2f) head=%.2f tail=%.2f"), CarTest.Current, *CarTest.CarId.ToString(),
			P.R, P.G, P.B, S.R, S.G, S.B, Vehicle->GetPaint().Primary.R, Vehicle->GetPaint().Primary.G, Vehicle->GetPaint().Primary.B, Vehicle->GetPaint().Secondary.R, Vehicle->GetPaint().Secondary.G, Vehicle->GetPaint().Secondary.B,
			Vehicle->Visuals->ReadLampIntensity(TEXT("head")), Vehicle->Visuals->ReadLampIntensity(TEXT("tail")));
	}
	if (Movement)
	{
		TArray<FString> Rows;
		Movement->DescribeWheels().ParseIntoArrayLines(Rows);
		for (const FString& Row : Rows)
		{
			UE_LOG(LogRoamVehicle, Display, TEXT("ROAM_CARTEST_WHEELS n=%d car=%s %s"), CarTest.Current, *CarTest.CarId.ToString(), *Row);
		}
	}
	TArray<FString> Problems;
	if (!bPhysics) { Problems.Add(TEXT("physics not ready")); }
	if (T.NumWheelsOnGround != 4) { Problems.Add(TEXT("not 4 wheels on ground")); }
	if (!bWheelsOk) { Problems.Add(TEXT("wheel hub height differs from the tyre radius by > 3 cm")); }
	if (CarTest.RestMaxSpeedKmh > 1.5f) { Problems.Add(TEXT("moves at rest")); }
	if (Tilt > 2.5f) { Problems.Add(TEXT("body not parallel to the ground")); }
	if (CarTest.RestMaxZ - CarTest.RestMinZ > 3.0f) { Problems.Add(TEXT("vertical jitter > 3 cm")); }
	UE_LOG(LogRoamVehicle, Display, TEXT("ROAM_CARTEST_REST_RESULT n=%d car=%s %s %s"), CarTest.Current, *CarTest.CarId.ToString(), Problems.Num() == 0 ? TEXT("PASS") : TEXT("FAIL"), *FString::Join(Problems, TEXT("; ")));
}

void URoamAutoDriveSubsystem::CarTestFinishDrive(ARoamVehicle* Vehicle)
{
	const FRoamVehicleTelemetry& T = Vehicle->GetTelemetry();
	const FVector Delta = Vehicle->GetActorLocation() - CarTest.DriveStartLocation;
	const FVector Right = FVector(-CarTest.DriveStartForward.Y, CarTest.DriveStartForward.X, 0.0);
	UE_LOG(LogRoamVehicle, Display, TEXT("ROAM_CARTEST_DRIVE n=%d car=%s seconds=%.1f endSpeed_kmh=%.1f maxSpeed_kmh=%.1f gear=%d rpm=%.0f t100_s=%.2f distance_m=%.0f lateralDrift_m=%.1f roll_max=%.2f pitch_max=%.2f vertG=[%.2f %.2f] slip_max_deg=%.1f yawrate_max=%.1f minWheels=%d zRise_cm=%.0f"),
		CarTest.Current, *CarTest.CarId.ToString(), CarTest.DriveSeconds, T.SpeedKmh, CarTest.DriveMaxSpeedKmh, T.Gear, T.RPM, CarTest.TimeTo100, FVector(Delta.X, Delta.Y, 0.0).Size() * 0.01, (Delta | Right) * 0.01,
		CarTest.DriveMaxRoll, CarTest.DriveMaxPitch, CarTest.DriveMinVertG, CarTest.DriveMaxVertG, CarTest.DriveMaxSlip, CarTest.DriveMaxYawRate, CarTest.DriveMinWheels, CarTest.DriveMaxZ - CarTest.DriveStartZ);
}

void URoamAutoDriveSubsystem::TickCarTest(float DeltaTime)
{
	if (CarTest.Phase == ECarTestPhase::Spawn)
	{
		CarTestBeginCar();
		return;
	}
	ARoamVehicle* Vehicle = ARoamVehicle::GetPlayerVehicle(this);
	if (!Vehicle)
	{
		CarTestEnd(TEXT("vehicle_lost"));
		return;
	}
	const FRoamVehicleTelemetry& T = Vehicle->GetTelemetry();
	CarTest.PhaseTime += DeltaTime;
	const float Time = CarTest.PhaseTime;

	switch (CarTest.Phase)
	{
	case ECarTestPhase::Settle:
	{
		if (Time >= 1.8f)
		{
			float GroundZ = 0.0f;
			FVector Normal = FVector::UpVector;
			if (GroundBelow(GetWorld(), Vehicle, Vehicle->GetActorLocation(), GroundZ, &Normal))
			{
				CarTest.RestMaxTiltDeg = FMath::Max(CarTest.RestMaxTiltDeg, FMath::RadiansToDegrees(FMath::Acos(FMath::Clamp(static_cast<float>(Vehicle->GetActorUpVector() | Normal), -1.0f, 1.0f))));
			}
			CarTest.RestMaxSpeedKmh = FMath::Max(CarTest.RestMaxSpeedKmh, T.SpeedKmh);
			CarTest.RestMinVertG = FMath::Min(CarTest.RestMinVertG, T.VertG);
			CarTest.RestMaxVertG = FMath::Max(CarTest.RestMaxVertG, T.VertG);
			CarTest.RestMinZ = FMath::Min(CarTest.RestMinZ, static_cast<float>(Vehicle->GetActorLocation().Z));
			CarTest.RestMaxZ = FMath::Max(CarTest.RestMaxZ, static_cast<float>(Vehicle->GetActorLocation().Z));
		}
		if (!CarTest.bShotTaken && Time >= 2.4f)
		{
			CarTest.bShotTaken = true;
			TakeShot(FString::Printf(TEXT("n=%d car=%s view=rest_chase"), CarTest.Current, *CarTest.CarId.ToString()));
		}
		if (Time >= 3.0f)
		{
			CarTestLogRest(Vehicle);
			CarTest.Phase = ECarTestPhase::Drive;
			CarTest.PhaseTime = 0.0f;
			CarTest.DriveStartLocation = Vehicle->GetActorLocation();
			CarTest.DriveStartForward = Vehicle->GetActorForwardVector();
			CarTest.DriveStartForward.Z = 0.0;
			CarTest.DriveStartForward.Normalize();
			CarTest.DriveStartZ = static_cast<float>(Vehicle->GetActorLocation().Z);
			CarTest.DriveMaxZ = CarTest.DriveStartZ;
			Vehicle->SetThrottle(1.0f);
			Vehicle->SetSteer(0.0f);
			Vehicle->SetBrake(0.0f);
		}
		break;
	}
	case ECarTestPhase::Drive:
	{
		CarTest.DriveMaxSpeedKmh = FMath::Max(CarTest.DriveMaxSpeedKmh, T.SpeedKmh);
		if (CarTest.TimeTo100 < 0.0f && T.SpeedKmh >= 100.0f)
		{
			CarTest.TimeTo100 = Time;
		}
		CarTest.DriveMaxRoll = FMath::Max(CarTest.DriveMaxRoll, FMath::Abs(T.RollDeg));
		CarTest.DriveMaxPitch = FMath::Max(CarTest.DriveMaxPitch, FMath::Abs(T.PitchDeg));
		CarTest.DriveMinVertG = FMath::Min(CarTest.DriveMinVertG, T.VertG);
		CarTest.DriveMaxVertG = FMath::Max(CarTest.DriveMaxVertG, T.VertG);
		CarTest.DriveMaxSlip = FMath::Max(CarTest.DriveMaxSlip, FMath::Abs(T.BodySlipAngleDeg));
		CarTest.DriveMaxYawRate = FMath::Max(CarTest.DriveMaxYawRate, FMath::Abs(T.YawRateDeg));
		CarTest.DriveMinWheels = FMath::Min(CarTest.DriveMinWheels, T.NumWheelsOnGround);
		CarTest.DriveMaxZ = FMath::Max(CarTest.DriveMaxZ, static_cast<float>(Vehicle->GetActorLocation().Z));

		// first 1.2 s: steering burst by hand (wheel animation check), then the autopilot keeps the car on the road at full throttle
		if (Time < 1.2f)
		{
			Vehicle->SetThrottle(0.7f);
			Vehicle->SetSteer(0.4f);
			CarTest.bSteerMarked = true;
		}
		else if (!bActive)
		{
			FString Message;
			SetGripFactor(3.0f);
			if (!StartAutoDrive(330.0f, 0.0f, Message))
			{
				Vehicle->SetSteer(0.0f);
				Vehicle->SetThrottle(1.0f);
				UE_LOG(LogRoamVehicle, Warning, TEXT("ROAM_CARTEST_DRIVE autopilot did not start (%s), driving straight"), *Message);
			}
			SetGripFactor(1.0f);
			GraceTimer = 100.0f;   // no recovery teleports during a measurement drive
		}
		if (CarTest.bSteerMarked && !CarTest.bWheelVisLogged && Time >= 1.1f && Vehicle->WheelMeshes.Num() == 4 && Vehicle->Visuals)
		{
			CarTest.bWheelVisLogged = true;
			const FVector Axle = Vehicle->WheelMeshes[0]->GetRelativeRotation().RotateVector(FVector::RightVector);
			const float MeshSteerYaw = FMath::RadiansToDegrees(FMath::Atan2(-static_cast<float>(Axle.X), static_cast<float>(Axle.Y)));
			const URoamCarDefinition* Def = Vehicle->GetCarDefinition();
			const float SteeringWheelDeg = (Vehicle->SteeringWheelMesh && Vehicle->SteeringWheelMesh->GetStaticMesh()) ? FMath::RadiansToDegrees(Vehicle->SteeringWheelMesh->GetRelativeRotation().Quaternion().GetAngle()) : -1.0f;
			UE_LOG(LogRoamVehicle, Display, TEXT("ROAM_CARTEST_WHEELVIS n=%d car=%s speed_kmh=%.0f telemetrySteerFL=%.1f FR=%.1f meshYawFL=%.1f frontAngle=%.1f steeringWheelMeshDeg=%.0f expected=%.0f spinRearLeft_deg_per_s_telemetry=%.0f spinDegAccum=%.0f"),
				CarTest.Current, *CarTest.CarId.ToString(), T.SpeedKmh, T.WheelSteerDeg[0], T.WheelSteerDeg[1], MeshSteerYaw, T.FrontWheelAngleDeg, SteeringWheelDeg,
				FMath::Abs(T.FrontWheelAngleDeg * (Def ? Def->Steering.SteeringRatio : 14.0f)), FMath::RadiansToDegrees(T.WheelAngVelRadS[2]), Vehicle->Visuals->GetWheelSpinDeg(2));
			CarTest.SpinDegAtMark = Vehicle->Visuals->GetWheelSpinDeg(2);
			CarTest.SpinMarkTime = Time;
		}
		if (CarTest.bWheelVisLogged && CarTest.SpinMarkTime > 0.0f && Time >= CarTest.SpinMarkTime + 0.1f && Vehicle->Visuals)
		{
			// rotation of the rear-left wheel mesh over ~0.1 s (unwrapped modulo 360 per frame is fine at this frame rate): compare with the telemetry spin
			float Diff = Vehicle->Visuals->GetWheelSpinDeg(2) - CarTest.SpinDegAtMark;
			Diff = FMath::UnwindDegrees(Diff);
			UE_LOG(LogRoamVehicle, Display, TEXT("ROAM_CARTEST_SPINVIS n=%d car=%s meshSpinDelta_deg_in_%.2fs=%.0f (mod 360)"), CarTest.Current, *CarTest.CarId.ToString(), Time - CarTest.SpinMarkTime, Diff);
			CarTest.SpinMarkTime = -1.0f;
		}
		if (Time >= CarTest.DriveSeconds)
		{
			CarTest.TailBefore = Vehicle->Visuals ? Vehicle->Visuals->ReadLampIntensity(TEXT("tail")) : -1.0f;
			CarTestFinishDrive(Vehicle);
			StopAutoDrive(TEXT("cartest_drive_done"));
			CarTest.Phase = ECarTestPhase::Brake;
			CarTest.PhaseTime = 0.0f;
			CarTest.BrakeStartSpeedKmh = T.SpeedKmh;
			CarTest.BrakeStartLocation = Vehicle->GetActorLocation();
			Vehicle->SetSteer(0.0f);
			Vehicle->SetThrottle(0.0f);
			Vehicle->SetBrake(1.0f);
		}
		break;
	}
	case ECarTestPhase::Brake:
	{
		if (!CarTest.bBrakeLampLogged && Time >= 0.6f && Vehicle->Visuals)
		{
			CarTest.bBrakeLampLogged = true;
			UE_LOG(LogRoamVehicle, Display, TEXT("ROAM_CARTEST_LAMPS n=%d car=%s tailBeforeBraking=%.2f tailWhileBraking=%.2f (material read-back) reverse=%.2f head=%.2f discGlow=%.2f"), CarTest.Current, *CarTest.CarId.ToString(),
				CarTest.TailBefore, Vehicle->Visuals->ReadLampIntensity(TEXT("tail")), Vehicle->Visuals->ReadLampIntensity(TEXT("reverse")), Vehicle->Visuals->ReadLampIntensity(TEXT("head")), Vehicle->Visuals->ReadLampIntensity(TEXT("disc")));
		}
		if (T.SpeedKmh < 3.0f || Time > 7.0f)
		{
			const float Distance = static_cast<float>(FVector::Dist2D(Vehicle->GetActorLocation(), CarTest.BrakeStartLocation)) * 0.01f;
			const float V0 = CarTest.BrakeStartSpeedKmh / 3.6f;
			UE_LOG(LogRoamVehicle, Display, TEXT("ROAM_CARTEST_BRAKE n=%d car=%s from_kmh=%.0f stopped_after_s=%.2f distance_m=%.1f avgDecel_g=%.2f endSpeed_kmh=%.1f"), CarTest.Current, *CarTest.CarId.ToString(), CarTest.BrakeStartSpeedKmh, Time, Distance,
				Time > 0.1f ? (V0 / Time) / 9.81f : 0.0f, T.SpeedKmh);
			Vehicle->SetBrake(0.0f);
			if (CarTest.bCams)
			{
				// camera views while the autopilot drives at 70 km/h
				FString Message;
				CarTest.Phase = ECarTestPhase::Cams;
				CarTest.PhaseTime = 0.0f;
				CarTest.CamIndex = 0;
				CarTest.bCamShot = false;
				if (!StartAutoDrive(70.0f, 0.0f, Message))
				{
					UE_LOG(LogRoamVehicle, Warning, TEXT("ROAM_CARTEST_CAMS autopilot did not start: %s"), *Message);
				}
				Vehicle->SetCameraMode(ERoamCameraMode::Chase);
			}
			else if (CarTest.Current >= CarTest.Last)
			{
				CarTestEnd(TEXT("done"));
			}
			else
			{
				++CarTest.Current;
				CarTest.Phase = ECarTestPhase::Spawn;
			}
		}
		break;
	}
	case ECarTestPhase::Cams:
	{
		static const ERoamCameraMode Modes[4] = { ERoamCameraMode::Chase, ERoamCameraMode::Hood, ERoamCameraMode::Cockpit, ERoamCameraMode::Bumper };
		static const TCHAR* const Names[4] = { TEXT("chase"), TEXT("hood"), TEXT("cockpit"), TEXT("bumper") };
		if (CarTest.CamIndex < 4)
		{
			if (Time < 0.05f)
			{
				Vehicle->SetCameraMode(Modes[CarTest.CamIndex]);
			}
			if (!CarTest.bCamShot && Time >= 3.0f)
			{
				CarTest.bCamShot = true;
				TakeShot(FString::Printf(TEXT("n=%d car=%s view=%s speed=%.0f"), CarTest.Current, *CarTest.CarId.ToString(), Names[CarTest.CamIndex], T.SpeedKmh));
			}
			if (Time >= 3.6f)
			{
				++CarTest.CamIndex;
				CarTest.PhaseTime = 0.0f;
				CarTest.bCamShot = false;
			}
		}
		else
		{
			StopAutoDrive(TEXT("cartest_cams_done"));
			Vehicle->SetCameraMode(ERoamCameraMode::Chase);
			if (CarTest.Current >= CarTest.Last)
			{
				CarTestEnd(TEXT("done"));
			}
			else
			{
				++CarTest.Current;
				CarTest.Phase = ECarTestPhase::Spawn;
			}
		}
		break;
	}
	default:
		break;
	}
}

// ------------------------------------------------------------------------------------------------------------------
// Console
// ------------------------------------------------------------------------------------------------------------------

ROAM_REGISTER_CONSOLE_COMMAND_CATEGORY("autodrive", "autodrive [on|off|stat|loop on|off|grip <f>|lane <n>] [speedKmh] [stopAfterKm]",
	"Road-following autopilot (pure pursuit in the lane, curvature-aware speed, follows the scenic loop). 'autodrive 150' = on at 150 km/h; without a speed the road's limit is used. Logs ROAM_AUTODRIVE_*.", "debug",
	[](const FRoamConsoleContext& Ctx) -> FString
	{
		URoamAutoDriveSubsystem* AutoDrive = URoamAutoDriveSubsystem::Get(Ctx.World);
		if (!AutoDrive)
		{
			return Ctx.Fail(TEXT("no autodrive system (game world only)"));
		}
		if (Ctx.NumArgs() == 0 || Ctx.Arg(0).Equals(TEXT("stat"), ESearchCase::IgnoreCase))
		{
			return AutoDrive->DescribeStatus();
		}
		const FString Sub = Ctx.Arg(0).ToLower();
		if (Sub == TEXT("off"))
		{
			AutoDrive->StopAutoDrive(TEXT("console"));
			return AutoDrive->DescribeStatus();
		}
		if (Sub == TEXT("grip"))
		{
			float Factor = 1.0f;
			if (!Ctx.GetFloat(1, Factor)) { return Ctx.Fail(TEXT("usage: autodrive grip <factor 0.2..4>")); }
			AutoDrive->SetGripFactor(Factor);
			return FString::Printf(TEXT("autodrive corner-grip factor %.2f"), Factor);
		}
		if (Sub == TEXT("lane"))
		{
			int32 Lane = 1;
			if (!Ctx.GetInt(1, Lane)) { return Ctx.Fail(TEXT("usage: autodrive lane <1|2>")); }
			AutoDrive->SetLane(Lane);
			return FString::Printf(TEXT("autodrive lane %d"), Lane);
		}
		if (Sub == TEXT("over"))
		{
			float Factor = -1.0f;
			Ctx.GetFloat(1, Factor);
			AutoDrive->SetOverspeed(Factor);
			return FString::Printf(TEXT("autodrive target = min(cruise cap, limit x %.2f)"), Factor);
		}
		if (Sub == TEXT("at"))
		{
			float SMeters = 0.0f;
			float Cruise2 = 0.0f;
			float Km2 = 0.0f;
			if (Ctx.NumArgs() < 3 || !Ctx.GetFloat(2, SMeters)) { return Ctx.Fail(TEXT("usage: autodrive at <roadId> <sMeters> [speedKmh] [stopAfterKm] [quit]")); }
			Ctx.GetFloat(3, Cruise2);
			Ctx.GetFloat(4, Km2);
			bool bQuit2 = false;
			for (const FString& Token : Ctx.Args) { bQuit2 |= Token.Equals(TEXT("quit"), ESearchCase::IgnoreCase); }
			AutoDrive->SetQuitWhenDone(bQuit2);
			FString Message2;
			if (!AutoDrive->PlaceOnRoad(Ctx.Arg(1), SMeters, Message2)) { return Ctx.Fail(Message2); }
			FString Message3;
			if (!AutoDrive->StartAutoDrive(Cruise2, Km2, Message3)) { return Ctx.Fail(Message3); }
			return Message2 + TEXT(" / ") + Message3;
		}
		if (Sub == TEXT("loop"))
		{
			bool bOn = true;
			Ctx.GetBool(1, bOn);
			AutoDrive->SetFollowLoop(bOn);
			return FString::Printf(TEXT("autodrive follows the scenic loop at junctions: %s"), bOn ? TEXT("yes") : TEXT("no (straightest arm)"));
		}
		int32 SpeedIndex = 1;
		if (Sub != TEXT("on"))
		{
			SpeedIndex = 0;   // 'autodrive 150'
		}
		float Cruise = 0.0f;
		float Km = 0.0f;
		Ctx.GetFloat(SpeedIndex, Cruise);
		Ctx.GetFloat(SpeedIndex + 1, Km);
		bool bQuit = false;
		for (const FString& Token : Ctx.Args)
		{
			bQuit |= Token.Equals(TEXT("quit"), ESearchCase::IgnoreCase);
		}
		AutoDrive->SetQuitWhenDone(bQuit);
		FString Message;
		if (!AutoDrive->StartAutoDrive(Cruise, Km, Message))
		{
			return Ctx.Fail(Message);
		}
		return Message;
	});

ROAM_REGISTER_CONSOLE_COMMAND_CATEGORY("cartest", "cartest [first] [last] [driveSeconds] [cams]",
	"Integration test of the garage cars on the road under the car: stance at rest, drive, brake, lamps, wheel animation (ROAM_CARTEST_* in the log). 'cams' also shoots chase/hood/cockpit/bumper views.", "debug",
	[](const FRoamConsoleContext& Ctx) -> FString
	{
		URoamAutoDriveSubsystem* AutoDrive = URoamAutoDriveSubsystem::Get(Ctx.World);
		if (!AutoDrive)
		{
			return Ctx.Fail(TEXT("no autodrive system (game world only)"));
		}
		int32 First = 1;
		int32 Last = 10;
		float Seconds = 9.0f;
		Ctx.GetInt(0, First);
		Last = First;
		if (Ctx.NumArgs() == 0) { Last = 10; }
		Ctx.GetInt(1, Last);
		Ctx.GetFloat(2, Seconds);
		bool bCams = false;
		bool bQuit = false;
		for (const FString& Token : Ctx.Args)
		{
			bCams |= Token.Equals(TEXT("cams"), ESearchCase::IgnoreCase);
			bQuit |= Token.Equals(TEXT("quit"), ESearchCase::IgnoreCase);
		}
		AutoDrive->SetQuitWhenDone(bQuit);
		FString Message;
		if (!AutoDrive->StartCarTest(First, Last, Seconds, bCams, Message))
		{
			return Ctx.Fail(Message);
		}
		return Message;
	});
