// Copyright Epic Games, Inc. All Rights Reserved.

#include "Core/RoamGameMode.h"

#include "Console/RoamConsoleSubsystem.h"
#include "Core/RoamCollision.h"
#include "Core/RoamGameInstance.h"
#include "Core/RoamHUD.h"
#include "Core/RoamLog.h"
#include "Core/RoamPlayerController.h"
#include "Core/RoamSettings.h"
#include "Data/RoamCarCatalog.h"
#include "Data/RoamCarDefinition.h"
#include "Data/RoamRoadNetwork.h"
#include "Data/RoamWorldDefinition.h"
#include "Engine/World.h"
#include "EngineUtils.h"
#include "GameFramework/PlayerStart.h"
#include "Kismet/GameplayStatics.h"
#include "Save/RoamSaveSubsystem.h"
#include "World/RoamSkyManager.h" // --- added by sky-weather ---
#include "Vehicle/RoamVehicle.h"

ARoamGameMode::ARoamGameMode()
{
	PlayerControllerClass = ARoamPlayerController::StaticClass();
	HUDClass = ARoamHUD::StaticClass();
	DefaultPawnClass = ARoamVehicle::StaticClass();
	bUseSeamlessTravel = false;
}

ARoamGameMode* ARoamGameMode::Get(const UObject* WorldContext)
{
	return Cast<ARoamGameMode>(UGameplayStatics::GetGameMode(WorldContext));
}

UClass* ARoamGameMode::GetDefaultPawnClassForController_Implementation(AController* InController)
{
	return GetDefault<URoamSettings>()->LoadVehicleClass().Get();
}

void ARoamGameMode::StartPlay()
{
	Super::StartPlay();
	// --- added by sky-weather --- day/night + weather visuals: spawn the sky manager when the map has none (it replaces the plain lighting actors).
	ARoamSkyManager::EnsureSkyManager(GetWorld());
	// The profile's time of day and weather are applied once the world's subsystems exist and the game started.
	if (URoamSaveSubsystem* Save = URoamSaveSubsystem::Get(this))
	{
		Save->ApplyProfileToWorld(GetWorld());
	}
}

// ------------------------------------------------------------------------------------------------------------------
// Spawning
// ------------------------------------------------------------------------------------------------------------------

URoamCarDefinition* ARoamGameMode::ResolveCarDefinition(FName RequestedCarId) const
{
	URoamGameInstance* GameInstance = URoamGameInstance::Get(this);
	URoamCarCatalog* Catalog = GameInstance ? GameInstance->GetCarCatalog() : nullptr;
	if (!Catalog || Catalog->GetNumCars() == 0)
	{
		return nullptr;
	}
	FName CarId = RequestedCarId;
	if (CarId.IsNone())
	{
		if (const URoamSaveSubsystem* Save = URoamSaveSubsystem::Get(this))
		{
			CarId = Save->GetProfile().CarId;
		}
	}
	if (CarId.IsNone())
	{
		CarId = GetDefault<URoamSettings>()->DefaultCarId;
	}
	if (!CarId.IsNone())
	{
		FString Error;
		if (URoamCarDefinition* Found = Catalog->ResolveCar(CarId.ToString(), &Error))
		{
			return Found;
		}
		UE_LOG(LogRoam, Warning, TEXT("Car '%s' not in the catalog (%s) - using the first car"), *CarId.ToString(), *Error);
	}
	return Catalog->GetCarByIndex(0);
}

FTransform ARoamGameMode::DropToGround(const FTransform& Transform) const
{
	FTransform Result = Transform;
	const UWorld* World = GetWorld();
	if (!World)
	{
		return Result;
	}
	const float Drop = GetDefault<URoamSettings>()->SpawnDropHeightCm;
	FHitResult Hit;
	const FVector Location = Transform.GetLocation();
	const FVector Start = Location + FVector(0.0, 0.0, 5000.0);
	const FVector End = Location - FVector(0.0, 0.0, 20000.0);
	if (World->LineTraceSingleByChannel(Hit, Start, End, RoamCollision::TraceWheel))
	{
		Result.SetLocation(FVector(Location.X, Location.Y, Hit.ImpactPoint.Z + Drop));
		UE_LOG(LogRoam, Display, TEXT("ROAM_GROUND_DROP hit=%s z=%.1f"), Hit.GetActor() ? *Hit.GetActor()->GetName() : TEXT("<none>"), Hit.ImpactPoint.Z);
	}
	else
	{
		UE_LOG(LogRoam, Warning, TEXT("ROAM_GROUND_DROP: nothing below %s on the wheel channel - keeping Z"), *Location.ToString());
	}
	return Result;
}

bool ARoamGameMode::SnapOffMedian(const UObject* WorldContext, FTransform& InOutTransform)
{
	URoamGameInstance* GameInstance = URoamGameInstance::Get(WorldContext);
	URoamRoadNetwork* Network = GameInstance ? GameInstance->GetRoadNetwork() : nullptr;
	if (!Network || Network->GetNumRoads() == 0)
	{
		return false;
	}
	FRoamRoadQuery Query;
	Query.Location = InOutTransform.GetLocation();
	Query.Heading = InOutTransform.GetRotation().GetForwardVector();
	Query.MaxDistanceCm = 700.0f;
	Query.MaxVerticalCm = 700.0f;
	FRoamRoadHit Hit;
	if (!Network->FindNearest(Query, Hit) || Hit.RoadClass != ERoamRoadClass::Highway || FMath::Abs(Hit.LateralCm) > 150.0f)
	{
		return false;
	}
	const int32 Lane = (Hit.Tangent | Query.Heading) >= 0.0 ? 1 : -1;
	FVector Position = Network->GetLanePosition(Hit, Lane);
	Position.Z += 60.0;
	UE_LOG(LogRoam, Display, TEXT("ROAM_SNAP_OFF_MEDIAN road=%s s=%.0f lateral=%.0f cm -> lane %d"), *Hit.RoadId.ToString(), Hit.S, Hit.LateralCm, Lane);
	InOutTransform.SetLocation(Position);
	return true;
}

FTransform ARoamGameMode::ComputeSpawnTransform(ERoamSpawnSource& OutSource) const
{
	const URoamSettings* Settings = GetDefault<URoamSettings>();
	URoamGameInstance* GameInstance = URoamGameInstance::Get(this);

	// 1. saved transform
	if (Settings->bRestoreSavedTransform)
	{
		if (const URoamSaveSubsystem* Save = URoamSaveSubsystem::Get(this))
		{
			if (Save->WasLoadedFromDisk() && Save->GetProfile().bHasLastTransform)
			{
				OutSource = ERoamSpawnSource::SavedTransform;
				FTransform T = Save->GetProfile().LastTransform;
				T.SetRotation(FQuat(FRotator(0.0f, T.Rotator().Yaw, 0.0f)));
				return DropToGround(T);
			}
		}
	}

	// 2. default POI
	if (GameInstance)
	{
		if (const URoamWorldDefinition* WorldDefinition = GameInstance->GetWorldDefinition())
		{
			if (const FRoamPoiDef* Poi = WorldDefinition->FindPoi(WorldDefinition->DefaultSpawnPoi))
			{
				OutSource = ERoamSpawnSource::WorldPoi;
				FTransform PoiTransform(FRotator(0.0f, Poi->YawDeg, 0.0f), Poi->Location);
				SnapOffMedian(this, PoiTransform);   // POIs on a highway sit on the centreline = on the median barrier
				return DropToGround(PoiTransform);
			}
		}
	}

	// 3. default road
	if (GameInstance)
	{
		if (URoamRoadNetwork* Network = GameInstance->GetRoadNetwork())
		{
			for (const FName RoadId : Settings->DefaultSpawnRoadIds)
			{
				FRoamRoadHit Hit;
				if (Network->SamplePosition(RoadId, Settings->DefaultSpawnS, Hit))
				{
					const FVector Position = Network->GetLanePosition(Hit, Settings->DefaultSpawnLane);
					const FVector Direction = URoamRoadNetwork::GetLaneDirection(Hit, Settings->DefaultSpawnLane);
					OutSource = ERoamSpawnSource::RoadNetwork;
					return DropToGround(FTransform(FRotator(0.0f, Direction.Rotation().Yaw, 0.0f), Position));
				}
			}
		}
	}

	// 4. player start
	if (const UWorld* World = GetWorld())
	{
		for (TActorIterator<APlayerStart> It(const_cast<UWorld*>(World)); It; ++It)
		{
			OutSource = ERoamSpawnSource::PlayerStart;
			FTransform T = It->GetActorTransform();
			T.SetScale3D(FVector::OneVector);
			return DropToGround(T);
		}
	}

	// 5. origin
	OutSource = ERoamSpawnSource::Origin;
	return DropToGround(FTransform(FRotator::ZeroRotator, FVector(0.0, 0.0, 100.0)));
}

ARoamVehicle* ARoamGameMode::SpawnVehicle(URoamCarDefinition* Definition, const FTransform& Transform)
{
	UWorld* World = GetWorld();
	if (!World)
	{
		return nullptr;
	}
	UClass* VehicleClass = GetDefaultPawnClassForController(nullptr);
	if (!VehicleClass)
	{
		VehicleClass = ARoamVehicle::StaticClass();
	}
	FActorSpawnParameters Params;
	Params.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;
	FTransform SpawnTransform = Transform;
	SpawnTransform.SetScale3D(FVector::OneVector);

	// Deferred: the definition must be assigned before BeginPlay applies it.
	ARoamVehicle* Vehicle = World->SpawnActorDeferred<ARoamVehicle>(VehicleClass, SpawnTransform, nullptr, nullptr, ESpawnActorCollisionHandlingMethod::AlwaysSpawn);
	if (!Vehicle)
	{
		UE_LOG(LogRoam, Error, TEXT("Failed to spawn the player vehicle (class %s)"), *VehicleClass->GetName());
		return nullptr;
	}
	Vehicle->InitialCarDefinition = Definition;
	Vehicle->FinishSpawning(SpawnTransform);
	return Vehicle;
}

APawn* ARoamGameMode::SpawnDefaultPawnAtTransform_Implementation(AController* NewPlayer, const FTransform& SpawnTransform)
{
	URoamCarDefinition* Definition = ResolveCarDefinition();
	ARoamVehicle* Vehicle = SpawnVehicle(Definition, SpawnTransform);
	if (Vehicle)
	{
		if (URoamSaveSubsystem* Save = URoamSaveSubsystem::Get(this))
		{
			if (Definition)
			{
				Save->GetProfile().CarId = Definition->CarId;
			}
		}
		UE_LOG(LogRoam, Display, TEXT("ROAM_SPAWN car=%s at (%.0f, %.0f, %.0f) yaw=%.1f"), Definition ? *Definition->CarId.ToString() : TEXT("<placeholder>"),
			SpawnTransform.GetLocation().X, SpawnTransform.GetLocation().Y, SpawnTransform.GetLocation().Z, SpawnTransform.Rotator().Yaw);
	}
	return Vehicle;
}

void ARoamGameMode::RestartPlayer(AController* NewPlayer)
{
	if (!NewPlayer || NewPlayer->IsPendingKillPending())
	{
		return;
	}
	// We never rely on a PlayerStart existing: the start transform comes from ComputeSpawnTransform.
	ERoamSpawnSource Source = ERoamSpawnSource::Origin;
	const FTransform Start = ComputeSpawnTransform(Source);
	UE_LOG(LogRoam, Display, TEXT("ROAM_SPAWN_SOURCE %s"), *Roam::EnumToString(Source));
	RestartPlayerAtTransform(NewPlayer, Start);
}

ARoamVehicle* ARoamGameMode::SpawnPlayerCar(FName CarId, const FTransform& Transform)
{
	APlayerController* PC = UGameplayStatics::GetPlayerController(this, 0);
	URoamCarDefinition* Definition = ResolveCarDefinition(CarId);
	if (!PC)
	{
		return nullptr;
	}
	if (!Definition && !CarId.IsNone())
	{
		UE_LOG(LogRoam, Warning, TEXT("SpawnPlayerCar: unknown car '%s'"), *CarId.ToString());
		return nullptr;
	}

	APawn* OldPawn = PC->GetPawn();
	// Make sure the profile points at the new car before BeginPlay pulls paint/tuning from it.
	if (URoamSaveSubsystem* Save = URoamSaveSubsystem::Get(this))
	{
		if (Definition)
		{
			Save->GetProfile().CarId = Definition->CarId;
			Save->MarkDirty();
		}
	}
	ARoamVehicle* Vehicle = SpawnVehicle(Definition, Transform);
	if (!Vehicle)
	{
		return nullptr;
	}
	if (OldPawn)
	{
		PC->UnPossess();
		OldPawn->Destroy();
	}
	PC->Possess(Vehicle);
	UE_LOG(LogRoam, Display, TEXT("ROAM_CAR_SWITCH car=%s"), Definition ? *Definition->CarId.ToString() : TEXT("<placeholder>"));
	return Vehicle;
}

ARoamVehicle* ARoamGameMode::SpawnPlayerCarAtCurrent(FName CarId)
{
	FTransform Transform = FTransform::Identity;
	if (const APawn* Pawn = UGameplayStatics::GetPlayerPawn(this, 0))
	{
		Transform = Pawn->GetActorTransform();
		FRotator Rotation = Transform.Rotator();
		Rotation.Pitch = 0.0f;
		Rotation.Roll = 0.0f;
		Transform.SetRotation(Rotation.Quaternion());
		Transform.AddToTranslation(FVector(0.0, 0.0, 30.0));
	}
	return SpawnPlayerCar(CarId, Transform);
}

// ------------------------------------------------------------------------------------------------------------------
// Console commands for cars
// ------------------------------------------------------------------------------------------------------------------

namespace
{
	bool ParseColor(const FString& Text, FLinearColor& OutColor)
	{
		struct FNamed { const TCHAR* Name; uint8 R; uint8 G; uint8 B; };
		static const FNamed Named[] =
		{
			{ TEXT("red"), 200, 20, 20 }, { TEXT("green"), 30, 150, 60 }, { TEXT("blue"), 30, 70, 200 }, { TEXT("yellow"), 240, 200, 20 },
			{ TEXT("orange"), 240, 110, 20 }, { TEXT("white"), 240, 240, 240 }, { TEXT("black"), 15, 15, 18 }, { TEXT("silver"), 170, 175, 182 },
			{ TEXT("gray"), 100, 105, 110 }, { TEXT("grey"), 100, 105, 110 }, { TEXT("purple"), 110, 40, 170 }, { TEXT("pink"), 235, 100, 160 },
			{ TEXT("teal"), 20, 150, 150 }, { TEXT("cyan"), 30, 200, 230 }, { TEXT("brown"), 100, 60, 30 }, { TEXT("gold"), 212, 170, 50 },
			{ TEXT("navy"), 15, 30, 90 }, { TEXT("lime"), 130, 220, 40 },
		};
		const FString T = Text.ToLower();
		for (const FNamed& Entry : Named)
		{
			if (T == Entry.Name)
			{
				OutColor = FLinearColor::FromSRGBColor(FColor(Entry.R, Entry.G, Entry.B));
				return true;
			}
		}
		if (T.StartsWith(TEXT("#")) || (T.Len() == 6 && !T.IsNumeric()))
		{
			const FColor Parsed = FColor::FromHex(T);
			OutColor = FLinearColor::FromSRGBColor(Parsed);
			return true;
		}
		return false;
	}
}

ROAM_REGISTER_CONSOLE_COMMAND_CATEGORY("cars", "cars", "List the garage: index, id, name, class and performance index.", "car",
	[](const FRoamConsoleContext& Ctx) -> FString
	{
		URoamGameInstance* GameInstance = Cast<URoamGameInstance>(Ctx.GameInstance);
		URoamCarCatalog* Catalog = GameInstance ? GameInstance->GetCarCatalog() : nullptr;
		if (!Catalog || Catalog->GetNumCars() == 0)
		{
			return Ctx.Fail(TEXT("the car catalog is empty or not configured (Project Settings > Roamline > Car Catalog)"));
		}
		const ARoamVehicle* Current = ARoamVehicle::GetPlayerVehicle(Ctx.World);
		FString Text = FString::Printf(TEXT("%d cars:"), Catalog->GetNumCars());
		for (int32 i = 0; i < Catalog->GetNumCars(); ++i)
		{
			const URoamCarDefinition* Def = Catalog->GetCarByIndex(i);
			Text += FString::Printf(TEXT("\n %s%2d  %-26s %-14s %s"), (Current && Def && Current->GetCarId() == Def->CarId) ? TEXT(">") : TEXT(" "), i + 1,
				Def ? *Def->CarId.ToString() : TEXT("<missing>"), Def ? *Def->DisplayName.ToString() : TEXT(""), Def ? *Def->GetClassLabel() : TEXT(""));
		}
		return Text;
	});

ROAM_REGISTER_CONSOLE_COMMAND_CATEGORY("car", "car <index|name>", "Switch to another car at the current position.", "car",
	[](const FRoamConsoleContext& Ctx) -> FString
	{
		ARoamGameMode* GameMode = ARoamGameMode::Get(Ctx.World);
		URoamGameInstance* GameInstance = Cast<URoamGameInstance>(Ctx.GameInstance);
		URoamCarCatalog* Catalog = GameInstance ? GameInstance->GetCarCatalog() : nullptr;
		if (!GameMode || !Catalog)
		{
			return Ctx.Fail(TEXT("no game mode / car catalog available"));
		}
		if (Ctx.NumArgs() == 0)
		{
			const ARoamVehicle* Current = ARoamVehicle::GetPlayerVehicle(Ctx.World);
			return FString::Printf(TEXT("current car: %s   usage: car <index|name>  (see 'cars')"), Current ? *Current->GetCarId().ToString() : TEXT("<none>"));
		}
		FString Error;
		URoamCarDefinition* Definition = Catalog->ResolveCar(Ctx.JoinFrom(0), &Error);
		if (!Definition)
		{
			return Ctx.Fail(Error);
		}
		ARoamVehicle* Vehicle = GameMode->SpawnPlayerCarAtCurrent(Definition->CarId);
		return Vehicle ? FString::Printf(TEXT("now driving %s"), *Definition->ToDebugString()) : Ctx.Fail(TEXT("could not spawn the car (see log)"));
	});

ROAM_REGISTER_CONSOLE_COMMAND_CATEGORY("respawn", "respawn", "Put the car back on the nearest road, upright.", "car",
	[](const FRoamConsoleContext& Ctx) -> FString
	{
		ARoamVehicle* Vehicle = ARoamVehicle::GetPlayerVehicle(Ctx.World);
		if (!Vehicle)
		{
			return Ctx.Fail(TEXT("no player vehicle"));
		}
		return Vehicle->ResetToRoad() ? FString(TEXT("back on the road")) : FString(TEXT("no road nearby - turned upright in place"));
	});

ROAM_REGISTER_CONSOLE_COMMAND_CATEGORY("reset", "reset", "Same as respawn: back on the nearest road, upright.", "car",
	[](const FRoamConsoleContext& Ctx) -> FString
	{
		ARoamVehicle* Vehicle = ARoamVehicle::GetPlayerVehicle(Ctx.World);
		if (!Vehicle)
		{
			return Ctx.Fail(TEXT("no player vehicle"));
		}
		return Vehicle->ResetToRoad() ? FString(TEXT("back on the road")) : FString(TEXT("no road nearby - turned upright in place"));
	});

ROAM_REGISTER_CONSOLE_COMMAND_CATEGORY("flip", "flip", "Turn the car upright where it is.", "car",
	[](const FRoamConsoleContext& Ctx) -> FString
	{
		ARoamVehicle* Vehicle = ARoamVehicle::GetPlayerVehicle(Ctx.World);
		if (!Vehicle)
		{
			return Ctx.Fail(TEXT("no player vehicle"));
		}
		Vehicle->FlipUpright();
		return TEXT("upright");
	});

ROAM_REGISTER_CONSOLE_COMMAND_CATEGORY("paint", "paint <colour|#RRGGBB> [gloss|matte|metallic]", "Repaint the car (named colour or hex) and optionally set the finish.", "car",
	[](const FRoamConsoleContext& Ctx) -> FString
	{
		ARoamVehicle* Vehicle = ARoamVehicle::GetPlayerVehicle(Ctx.World);
		if (!Vehicle)
		{
			return Ctx.Fail(TEXT("no player vehicle"));
		}
		if (Ctx.NumArgs() == 0)
		{
			return Ctx.Fail(TEXT("usage: paint <red|green|blue|yellow|orange|white|black|silver|gray|purple|pink|teal|cyan|brown|gold|navy|lime|#RRGGBB> [gloss|matte|metallic]"));
		}
		FRoamPaint Paint = Vehicle->GetPaint();
		if (!ParseColor(Ctx.Arg(0), Paint.Primary))
		{
			return Ctx.Fail(FString::Printf(TEXT("unknown colour '%s'"), *Ctx.Arg(0)));
		}
		if (Ctx.NumArgs() > 1 && !Roam::ParseEnum(Ctx.Arg(1), Paint.Finish))
		{
			return Ctx.Fail(TEXT("finish must be gloss, matte or metallic"));
		}
		Vehicle->SetPaint(Paint);
		if (URoamSaveSubsystem* Save = Ctx.GameInstance ? Ctx.GameInstance->GetSubsystem<URoamSaveSubsystem>() : nullptr)
		{
			Save->SetPaintForCar(Vehicle->GetCarId(), Paint);
		}
		return FString::Printf(TEXT("painted %s %s"), *Ctx.Arg(0), *Roam::EnumToString(Paint.Finish));
	});

ROAM_REGISTER_CONSOLE_COMMAND_CATEGORY("assist", "assist [tcs|stm|abs|steer|auto|line] [on|off]", "Show or toggle a driving assist.", "car",
	[](const FRoamConsoleContext& Ctx) -> FString
	{
		ARoamVehicle* Vehicle = ARoamVehicle::GetPlayerVehicle(Ctx.World);
		if (!Vehicle)
		{
			return Ctx.Fail(TEXT("no player vehicle"));
		}
		if (Ctx.NumArgs() >= 1)
		{
			ERoamAssist Assist;
			if (!Roam::ParseAssistName(Ctx.Arg(0), Assist))
			{
				return Ctx.Fail(TEXT("unknown assist. Names: tcs, stm, abs, steer, auto, line"));
			}
			bool bOn = !Vehicle->GetAssists().Get(Assist);
			if (Ctx.NumArgs() >= 2 && !Ctx.GetBool(1, bOn))
			{
				return Ctx.Fail(TEXT("usage: assist <name> on|off"));
			}
			Vehicle->SetAssist(Assist, bOn);
		}
		FString Text = TEXT("assists:");
		for (ERoamAssist Assist : TEnumRange<ERoamAssist>())
		{
			Text += FString::Printf(TEXT(" %s=%s"), *Roam::AssistToShortName(Assist), Vehicle->GetAssists().Get(Assist) ? TEXT("on") : TEXT("off"));
		}
		return Text;
	});

ROAM_REGISTER_CONSOLE_COMMAND_CATEGORY("camera", "camera [chase|hood|cockpit|bumper|freelook]", "Show or set the camera mode (no argument cycles).", "car",
	[](const FRoamConsoleContext& Ctx) -> FString
	{
		ARoamVehicle* Vehicle = ARoamVehicle::GetPlayerVehicle(Ctx.World);
		if (!Vehicle)
		{
			return Ctx.Fail(TEXT("no player vehicle"));
		}
		if (Ctx.NumArgs() == 0)
		{
			Vehicle->CycleCameraMode();
		}
		else
		{
			ERoamCameraMode Mode;
			if (!Roam::ParseEnum(Ctx.Arg(0), Mode) || Mode == ERoamCameraMode::Count)
			{
				return Ctx.Fail(TEXT("camera modes: chase, hood, cockpit, bumper, freelook"));
			}
			Vehicle->SetCameraMode(Mode);
		}
		return FString::Printf(TEXT("camera: %s"), *Roam::EnumToString(Vehicle->GetCameraMode()));
	});
