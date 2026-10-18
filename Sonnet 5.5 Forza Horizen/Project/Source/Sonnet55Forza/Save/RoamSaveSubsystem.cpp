// Copyright Epic Games, Inc. All Rights Reserved.

#include "Save/RoamSaveSubsystem.h"

#include "Console/RoamConsoleSubsystem.h"
#include "Core/RoamLog.h"
#include "Core/RoamSettings.h"
#include "Engine/Engine.h"
#include "Engine/GameInstance.h"
#include "Engine/World.h"
#include "Async/Async.h"
#include "Kismet/GameplayStatics.h"
#include "Misc/Crc.h"
#include "Serialization/MemoryReader.h"
#include "Serialization/MemoryWriter.h"
#include "Save/RoamSaveGame.h"
#include "Vehicle/RoamVehicle.h"
#include "World/RoamTimeWeatherSubsystem.h"

namespace
{
	constexpr uint32 EnvelopeMagic = 0x4D414F52u; // 'ROAM' little endian
}

URoamSaveSubsystem* URoamSaveSubsystem::Get(const UObject* WorldContext)
{
	const UWorld* World = GEngine ? GEngine->GetWorldFromContextObject(WorldContext, EGetWorldErrorMode::ReturnNull) : nullptr;
	const UGameInstance* GameInstance = World ? World->GetGameInstance() : nullptr;
	return GameInstance ? GameInstance->GetSubsystem<URoamSaveSubsystem>() : nullptr;
}

FString URoamSaveSubsystem::GetSlotName() const
{
	const URoamSettings* Settings = GetDefault<URoamSettings>();
	return Settings && !Settings->SaveSlotName.IsEmpty() ? Settings->SaveSlotName : FString(TEXT("Profile"));
}

void URoamSaveSubsystem::Initialize(FSubsystemCollectionBase& Collection)
{
	Super::Initialize(Collection);

	// Defaults first, so every code path has a valid profile even if loading fails or is disabled.
	Profile = FRoamProfile();
	const URoamSettings* Settings = GetDefault<URoamSettings>();
	Profile.CarId = Settings->DefaultCarId;
	Profile.GameHour = Settings->DefaultGameHour;
	Profile.Weather = Settings->DefaultWeather;

	if (Settings->bAutoLoadProfile)
	{
		LoadProfile();
	}
}

void URoamSaveSubsystem::Deinitialize()
{
	Super::Deinitialize();
}

void URoamSaveSubsystem::MarkDirty()
{
	bDirty = true;
	OnProfileChanged.Broadcast();
}

// ------------------------------------------------------------------------------------------------------------------
// Persistence
// ------------------------------------------------------------------------------------------------------------------

void URoamSaveSubsystem::SanitizeProfile(FRoamProfile& P)
{
	P.GameHour = FMath::Fmod(FMath::Max(P.GameHour, 0.0f), 24.0f);
	if (static_cast<uint8>(P.Weather) >= static_cast<uint8>(ERoamWeather::Count))
	{
		P.Weather = ERoamWeather::Clear;
	}
	if (P.LastTransform.ContainsNaN() || !P.LastTransform.GetRotation().IsNormalized())
	{
		P.LastTransform = FTransform::Identity;
		P.bHasLastTransform = false;
	}
	FRoamPlayerSettings& S = P.Settings;
	S.NotificationSeconds = FMath::Clamp(S.NotificationSeconds, 1.0f, 10.0f);
	S.TrafficDensity = FMath::Clamp(S.TrafficDensity, 0.0f, 1.0f);
	S.MasterVolume = FMath::Clamp(S.MasterVolume, 0.0f, 1.0f);
	S.EngineVolume = FMath::Clamp(S.EngineVolume, 0.0f, 1.0f);
	S.LookSensitivity = FMath::Clamp(S.LookSensitivity, 0.1f, 5.0f);
	S.Assists.SteeringAssist = FMath::Clamp(S.Assists.SteeringAssist, 0.0f, 1.0f);
	if (static_cast<uint8>(S.DefaultCameraMode) >= static_cast<uint8>(ERoamCameraMode::Photo))
	{
		S.DefaultCameraMode = ERoamCameraMode::Chase;
	}
	P.Credits = FMath::Max<int64>(P.Credits, 0);
	P.TotalXp = FMath::Max<int64>(P.TotalXp, 0);
	for (TPair<FName, int32>& Pair : P.ActivityStars)
	{
		Pair.Value = FMath::Clamp(Pair.Value, 0, 3);
	}
}

URoamSaveGame* URoamSaveSubsystem::CreateSaveObject() const
{
	URoamSaveGame* SaveObject = Cast<URoamSaveGame>(UGameplayStatics::CreateSaveGameObject(URoamSaveGame::StaticClass()));
	if (SaveObject)
	{
		SaveObject->Version = URoamSaveGame::CurrentVersion;
		SaveObject->Profile = Profile;
		SaveObject->SavedAtUtc = FDateTime::UtcNow().ToIso8601();
	}
	return SaveObject;
}

void URoamSaveSubsystem::PackEnvelope(const TArray<uint8>& Payload, TArray<uint8>& OutData)
{
	OutData.Reset();
	FMemoryWriter Writer(OutData);
	uint32 Magic = EnvelopeMagic;
	int32 EnvelopeVersion = 1;
	int32 Size = Payload.Num();
	uint32 Crc = FCrc::MemCrc32(Payload.GetData(), Payload.Num());
	Writer << Magic << EnvelopeVersion << Size << Crc;
	OutData.Append(Payload);
}

bool URoamSaveSubsystem::UnpackEnvelope(const TArray<uint8>& Data, TArray<uint8>& OutPayload)
{
	OutPayload.Reset();
	constexpr int32 HeaderSize = 16;
	if (Data.Num() < HeaderSize)
	{
		return false;
	}
	FMemoryReader Reader(Data);
	uint32 Magic = 0;
	int32 EnvelopeVersion = 0;
	int32 Size = 0;
	uint32 Crc = 0;
	Reader << Magic << EnvelopeVersion << Size << Crc;
	if (Magic != EnvelopeMagic || EnvelopeVersion != 1 || Size < 0 || Size != Data.Num() - HeaderSize)
	{
		return false;
	}
	if (FCrc::MemCrc32(Data.GetData() + HeaderSize, Size) != Crc)
	{
		return false;
	}
	OutPayload.Append(Data.GetData() + HeaderSize, Size);
	return true;
}

bool URoamSaveSubsystem::LoadProfile()
{
	bLoadedFromDisk = false;
	const FString Slot = GetSlotName();
	if (!UGameplayStatics::DoesSaveGameExist(Slot, 0))
	{
		UE_LOG(LogRoamSave, Log, TEXT("No save in slot '%s' - starting with the default profile"), *Slot);
		return false;
	}

	TArray<uint8> Raw;
	TArray<uint8> Payload;
	if (!UGameplayStatics::LoadDataFromSlot(Raw, Slot, 0) || !UnpackEnvelope(Raw, Payload))
	{
		UE_LOG(LogRoamSave, Warning, TEXT("Save slot '%s' is unreadable or damaged (%d bytes) - using the default profile"), *Slot, Raw.Num());
		return false;
	}
	URoamSaveGame* Loaded = Cast<URoamSaveGame>(UGameplayStatics::LoadGameFromMemory(Payload));
	if (!Loaded)
	{
		UE_LOG(LogRoamSave, Warning, TEXT("Save slot '%s' has no valid Roamline profile - using the default profile"), *Slot);
		return false;
	}
	if (Loaded->Version > URoamSaveGame::CurrentVersion)
	{
		UE_LOG(LogRoamSave, Warning, TEXT("Save slot '%s' has version %d, newer than %d - using the default profile"), *Slot, Loaded->Version, URoamSaveGame::CurrentVersion);
		return false;
	}
	Profile = Loaded->Profile;
	SanitizeProfile(Profile);
	bLoadedFromDisk = true;
	bDirty = false;
	UE_LOG(LogRoamSave, Display, TEXT("ROAM_SAVE_LOADED slot=%s car=%s hour=%.2f weather=%s saved=%s"), *Slot, *Profile.CarId.ToString(), Profile.GameHour, *Roam::EnumToString(Profile.Weather), *Loaded->SavedAtUtc);
	OnProfileChanged.Broadcast();
	return true;
}

bool URoamSaveSubsystem::SaveProfile(bool bCaptureWorldState)
{
	if (bCaptureWorldState)
	{
		CaptureRuntimeState(GetGameInstance() ? GetGameInstance()->GetWorld() : nullptr);
	}
	const FString Slot = GetSlotName();
	TArray<uint8> Data;
	if (!BuildSaveData(Data))
	{
		UE_LOG(LogRoamSave, Error, TEXT("Could not serialise the profile"));
		return false;
	}
	const bool bOk = UGameplayStatics::SaveDataToSlot(Data, Slot, 0);
	if (bOk)
	{
		bDirty = false;
	}
	UE_LOG(LogRoamSave, Display, TEXT("ROAM_SAVE_WRITTEN slot=%s ok=%d bytes=%d"), *Slot, bOk ? 1 : 0, Data.Num());
	return bOk;
}

void URoamSaveSubsystem::AsyncSaveProfile(bool bCaptureWorldState)
{
	if (bCaptureWorldState)
	{
		CaptureRuntimeState(GetGameInstance() ? GetGameInstance()->GetWorld() : nullptr);
	}
	TArray<uint8> Data;
	if (!BuildSaveData(Data))
	{
		return;
	}
	bDirty = false;
	const FString Slot = GetSlotName();
	// Serialisation happened on the game thread; only the file write runs on a worker.
	Async(EAsyncExecution::ThreadPool, [Data = MoveTemp(Data), Slot]()
	{
		UGameplayStatics::SaveDataToSlot(Data, Slot, 0);
	});
}

bool URoamSaveSubsystem::BuildSaveData(TArray<uint8>& OutData) const
{
	URoamSaveGame* SaveObject = CreateSaveObject();
	TArray<uint8> Payload;
	if (!SaveObject || !UGameplayStatics::SaveGameToMemory(SaveObject, Payload))
	{
		return false;
	}
	PackEnvelope(Payload, OutData);
	return true;
}

void URoamSaveSubsystem::ResetProfile(bool bDeleteSlot)
{
	const URoamSettings* Settings = GetDefault<URoamSettings>();
	Profile = FRoamProfile();
	Profile.CarId = Settings->DefaultCarId;
	Profile.GameHour = Settings->DefaultGameHour;
	Profile.Weather = Settings->DefaultWeather;
	bLoadedFromDisk = false;
	if (bDeleteSlot)
	{
		UGameplayStatics::DeleteGameInSlot(GetSlotName(), 0);
	}
	bDirty = true;
	OnProfileChanged.Broadcast();
}

// ------------------------------------------------------------------------------------------------------------------
// Runtime bridge
// ------------------------------------------------------------------------------------------------------------------

void URoamSaveSubsystem::CaptureRuntimeState(UWorld* World)
{
	if (!World)
	{
		return;
	}
	if (const ARoamVehicle* Vehicle = ARoamVehicle::GetPlayerVehicle(World))
	{
		if (!Vehicle->GetCarId().IsNone())
		{
			Profile.CarId = Vehicle->GetCarId();
			Profile.PaintByCar.Add(Profile.CarId, Vehicle->GetPaint());
			Profile.Paint = Vehicle->GetPaint();
		}
		Profile.Tuning = Vehicle->GetTuning();
		Profile.Settings.Assists = Vehicle->GetAssists();
		Profile.LastTransform = Vehicle->GetActorTransform();
		Profile.bHasLastTransform = true;
	}
	if (const URoamTimeWeatherSubsystem* TimeWeather = World->GetSubsystem<URoamTimeWeatherSubsystem>())
	{
		Profile.GameHour = TimeWeather->GetGameHour();
		Profile.Weather = TimeWeather->GetWeather();
	}
}

void URoamSaveSubsystem::ApplyProfileToWorld(UWorld* World) const
{
	if (!World)
	{
		return;
	}
	if (URoamTimeWeatherSubsystem* TimeWeather = World->GetSubsystem<URoamTimeWeatherSubsystem>())
	{
		if (bLoadedFromDisk)
		{
			TimeWeather->SetGameHour(Profile.GameHour);
			TimeWeather->SetWeather(Profile.Weather, 0.0f);
		}
	}
}

// ------------------------------------------------------------------------------------------------------------------
// Typed helpers
// ------------------------------------------------------------------------------------------------------------------

bool URoamSaveSubsystem::SubmitPersonalBest(FName ActivityId, float Value, bool bLowerIsBetter)
{
	float* Existing = Profile.PersonalBests.Find(ActivityId);
	const bool bBetter = !Existing || (bLowerIsBetter ? Value < *Existing - 0.01f : Value > *Existing + 0.01f);
	if (bBetter)
	{
		Profile.PersonalBests.Add(ActivityId, Value);
		MarkDirty();
	}
	return bBetter;
}

bool URoamSaveSubsystem::GetPersonalBest(FName ActivityId, float& OutValue) const
{
	if (const float* Existing = Profile.PersonalBests.Find(ActivityId))
	{
		OutValue = *Existing;
		return true;
	}
	return false;
}

bool URoamSaveSubsystem::SubmitStars(FName ActivityId, int32 Stars)
{
	Stars = FMath::Clamp(Stars, 0, 3);
	int32& Stored = Profile.ActivityStars.FindOrAdd(ActivityId);
	if (Stars > Stored)
	{
		Stored = Stars;
		MarkDirty();
		return true;
	}
	return false;
}

void URoamSaveSubsystem::AddXp(int64 Xp)
{
	if (Xp > 0)
	{
		Profile.TotalXp += Xp;
		MarkDirty();
	}
}

bool URoamSaveSubsystem::MarkCollected(FName CollectibleId)
{
	bool bAlreadyCollected = false;
	Profile.Collected.Add(CollectibleId, &bAlreadyCollected);
	if (!bAlreadyCollected)
	{
		MarkDirty();
	}
	return !bAlreadyCollected;
}

FRoamPaint URoamSaveSubsystem::GetPaintForCar(FName CarId) const
{
	if (const FRoamPaint* Found = Profile.PaintByCar.Find(CarId))
	{
		return *Found;
	}
	return Profile.Paint;
}

void URoamSaveSubsystem::SetPaintForCar(FName CarId, const FRoamPaint& Paint)
{
	Profile.PaintByCar.Add(CarId, Paint);
	if (CarId == Profile.CarId)
	{
		Profile.Paint = Paint;
	}
	MarkDirty();
}

// ------------------------------------------------------------------------------------------------------------------
// Console commands
// ------------------------------------------------------------------------------------------------------------------

ROAM_REGISTER_CONSOLE_COMMAND_CATEGORY("save", "save", "Write the profile (car, paint, position, time, weather, settings, bests) to disk.", "save",
	[](const FRoamConsoleContext& Ctx) -> FString
	{
		URoamSaveSubsystem* Save = Ctx.GameInstance ? Ctx.GameInstance->GetSubsystem<URoamSaveSubsystem>() : nullptr;
		if (!Save)
		{
			return Ctx.Fail(TEXT("no save subsystem"));
		}
		return Save->SaveProfile(true) ? FString(TEXT("profile saved")) : Ctx.Fail(TEXT("saving failed (see log)"));
	});

ROAM_REGISTER_CONSOLE_COMMAND_CATEGORY("load", "load", "Reload the saved profile and apply time/weather (the car is restored at the next respawn).", "save",
	[](const FRoamConsoleContext& Ctx) -> FString
	{
		URoamSaveSubsystem* Save = Ctx.GameInstance ? Ctx.GameInstance->GetSubsystem<URoamSaveSubsystem>() : nullptr;
		if (!Save)
		{
			return Ctx.Fail(TEXT("no save subsystem"));
		}
		if (!Save->LoadProfile())
		{
			return Ctx.Fail(TEXT("nothing to load (no usable save)"));
		}
		Save->ApplyProfileToWorld(Ctx.World);
		return FString::Printf(TEXT("profile loaded: car %s, hour %.1f, weather %s"), *Save->GetProfile().CarId.ToString(), Save->GetProfile().GameHour, *Roam::EnumToString(Save->GetProfile().Weather));
	});

ROAM_REGISTER_CONSOLE_COMMAND_CATEGORY("resetprofile", "resetprofile [delete]", "Reset the profile to defaults (optionally deleting the save slot).", "save",
	[](const FRoamConsoleContext& Ctx) -> FString
	{
		URoamSaveSubsystem* Save = Ctx.GameInstance ? Ctx.GameInstance->GetSubsystem<URoamSaveSubsystem>() : nullptr;
		if (!Save)
		{
			return Ctx.Fail(TEXT("no save subsystem"));
		}
		const bool bDelete = Ctx.NumArgs() > 0 && Ctx.Arg(0).Equals(TEXT("delete"), ESearchCase::IgnoreCase);
		Save->ResetProfile(bDelete);
		return bDelete ? TEXT("profile reset and save slot deleted") : TEXT("profile reset (slot kept until the next save)");
	});

ROAM_REGISTER_CONSOLE_COMMAND_CATEGORY("profile", "profile", "Print a summary of the current profile.", "save",
	[](const FRoamConsoleContext& Ctx) -> FString
	{
		const URoamSaveSubsystem* Save = Ctx.GameInstance ? Ctx.GameInstance->GetSubsystem<URoamSaveSubsystem>() : nullptr;
		if (!Save)
		{
			return Ctx.Fail(TEXT("no save subsystem"));
		}
		const FRoamProfile& P = Save->GetProfile();
		return FString::Printf(TEXT("car=%s hour=%.2f weather=%s bests=%d stars=%d xp=%lld loadedFromDisk=%d dirty=%d"),
			*P.CarId.ToString(), P.GameHour, *Roam::EnumToString(P.Weather), P.PersonalBests.Num(), P.ActivityStars.Num(), P.TotalXp, Save->WasLoadedFromDisk() ? 1 : 0, Save->IsDirty() ? 1 : 0);
	});
