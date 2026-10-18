// Copyright Epic Games, Inc. All Rights Reserved.

#pragma once

#include "CoreMinimal.h"
#include "Core/RoamTypes.h"
#include "Subsystems/GameInstanceSubsystem.h"
#include "RoamSaveSubsystem.generated.h"

class URoamSaveGame;

DECLARE_MULTICAST_DELEGATE(FRoamOnProfileChanged);

/**
 * Owns the player's profile (FRoamProfile) for the whole session and persists it (Docs/ARCHITECTURE.md section 3).
 *
 *  - The profile is ALWAYS valid: if no save exists or it cannot be loaded (missing, corrupt, newer version) the defaults are used
 *    and a warning is logged - the game never fails to start because of a save.
 *  - Systems read/write through GetProfile() / GetSettings() and call MarkDirty() (or the typed helpers); SaveProfile() writes the
 *    slot. Saving happens on request (console `save`, menu), on level end and on a quit request; AsyncSaveProfile() is used while driving.
 *  - Dynamic objects (traffic, FX) are never persisted; the world is rebuilt from the profile (car, transform, time, weather).
 */
UCLASS()
class SONNET55FORZA_API URoamSaveSubsystem : public UGameInstanceSubsystem
{
	GENERATED_BODY()

public:
	static URoamSaveSubsystem* Get(const UObject* WorldContext);

	//~ Begin USubsystem
	virtual void Initialize(FSubsystemCollectionBase& Collection) override;
	virtual void Deinitialize() override;
	//~ End USubsystem

	// ---- profile access --------------------------------------------------------------------------------------------
	FRoamProfile& GetProfile() { return Profile; }
	const FRoamProfile& GetProfile() const { return Profile; }
	FRoamPlayerSettings& GetSettings() { return Profile.Settings; }
	const FRoamPlayerSettings& GetSettings() const { return Profile.Settings; }

	/** True if a save existed and was loaded successfully this session (or after the last LoadProfile). */
	bool WasLoadedFromDisk() const { return bLoadedFromDisk; }

	/** Tell listeners (UI, vehicle) that profile content changed. */
	void MarkDirty();
	bool IsDirty() const { return bDirty; }

	// ---- persistence -----------------------------------------------------------------------------------------------
	/** Loads the slot. Returns false (and keeps/creates the default profile) if there is nothing usable. */
	UFUNCTION(BlueprintCallable, Category = "Roam|Save")
	bool LoadProfile();

	/** Captures the runtime state (car, transform, time, weather) when a world is running, then writes the slot synchronously. */
	UFUNCTION(BlueprintCallable, Category = "Roam|Save")
	bool SaveProfile(bool bCaptureWorldState = true);

	/** Same as SaveProfile but writes on a worker thread (no hitch while driving). */
	void AsyncSaveProfile(bool bCaptureWorldState = true);

	/** Resets to defaults; optionally deletes the slot on disk. */
	UFUNCTION(BlueprintCallable, Category = "Roam|Save")
	void ResetProfile(bool bDeleteSlot);

	/** Clamps and repairs a profile (hour range, enum range, settings ranges). Public for tests. */
	static void SanitizeProfile(FRoamProfile& InOutProfile);

	/** Builds the save object for the current profile (also used by the round-trip test). */
	URoamSaveGame* CreateSaveObject() const;

	/**
	 * Integrity envelope around the engine's save data:  "ROAM" | int32 envelope version | int32 payload size | uint32 CRC32 | payload.
	 * Why: UGameplayStatics::LoadGameFromMemory/LoadGameFromSlot do NOT validate their input - in 5.8.2 a truncated or foreign
	 * file makes the header reader try to build an FName from garbage and the engine asserts. Slot data is therefore only handed
	 * to the engine after size, magic and CRC checked out, so a damaged save degrades to "default profile" instead of a crash.
	 */
	static void PackEnvelope(const TArray<uint8>& Payload, TArray<uint8>& OutData);
	/** Returns false (and an empty payload) for anything that is not an intact envelope. */
	static bool UnpackEnvelope(const TArray<uint8>& Data, TArray<uint8>& OutPayload);

	// ---- runtime state bridge --------------------------------------------------------------------------------------
	/** Copies car, paint, transform, hour and weather of the running world into the profile. */
	void CaptureRuntimeState(UWorld* World);

	/** Pushes hour/weather (and the time scale) of the profile into the time/weather subsystem of World. */
	void ApplyProfileToWorld(UWorld* World) const;

	// ---- typed helpers ---------------------------------------------------------------------------------------------
	/** Records a result; returns true if it is a new personal best (lower is better for times). */
	bool SubmitPersonalBest(FName ActivityId, float Value, bool bLowerIsBetter);
	bool GetPersonalBest(FName ActivityId, float& OutValue) const;
	/** Stars only ever increase; returns true if the stored value rose. */
	bool SubmitStars(FName ActivityId, int32 Stars);
	void AddXp(int64 Xp);
	/** Returns true if the id was not collected before. */
	bool MarkCollected(FName CollectibleId);

	/** The paint stored for a car (falls back to the profile's current paint, then defaults). */
	FRoamPaint GetPaintForCar(FName CarId) const;
	void SetPaintForCar(FName CarId, const FRoamPaint& Paint);

	FRoamOnProfileChanged OnProfileChanged;

private:
	FString GetSlotName() const;
	bool BuildSaveData(TArray<uint8>& OutData) const;

	FRoamProfile Profile;
	bool bLoadedFromDisk = false;
	bool bDirty = false;
};
