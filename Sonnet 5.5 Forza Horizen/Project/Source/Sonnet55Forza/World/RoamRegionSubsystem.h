// Copyright Epic Games, Inc. All Rights Reserved.

#pragma once

#include "CoreMinimal.h"
#include "Core/RoamTypes.h"
#include "Subsystems/WorldSubsystem.h"
#include "RoamRegionSubsystem.generated.h"

struct FRoamRegionDef;
class URoamWorldDefinition;

DECLARE_MULTICAST_DELEGATE_TwoParams(FRoamOnRegionChanged, FName /*OldRegionId*/, FName /*NewRegionId*/);

/**
 * Knows which region of the world the player is in (Docs/WORLD_SPEC.md section 2), shows the region-name popup when the border is
 * crossed, and resolves `tp <region|poi>` targets. Data comes from URoamWorldDefinition (regions are priority-ordered
 * rectangles). Polls the player position at 4 Hz - there is no per-actor tick.
 *
 * Popup rules (Docs/Tech/FH5_traffic_hud_photo.md 3.3): a region must be left by RegionHysteresisCm before the popup of another
 * region is shown, and the same region does not pop up again within RegionPopupCooldownSec.
 *
 * ---- OWNER: world/regions agent ---------------------------------------------------------------------------------------------
 * The skeleton implements lookup, change detection, popup trigger and the console commands `tp` and `regions`; the owner adds
 * climate-zone effects (weather weights per zone), ambient life zones and fast-travel polish.
 */
UCLASS()
class SONNET55FORZA_API URoamRegionSubsystem : public UTickableWorldSubsystem
{
	GENERATED_BODY()

public:
	static URoamRegionSubsystem* Get(const UObject* WorldContext);

	//~ Begin USubsystem / UWorldSubsystem
	virtual void Initialize(FSubsystemCollectionBase& Collection) override;
	virtual bool DoesSupportWorldType(const EWorldType::Type WorldType) const override;
	//~ End

	//~ Begin FTickableGameObject
	virtual void Tick(float DeltaTime) override;
	virtual TStatId GetStatId() const override { RETURN_QUICK_DECLARE_CYCLE_STAT(URoamRegionSubsystem, STATGROUP_Tickables); }
	//~ End

	/** Id of the region the player is in (NAME_None outside every region or without a world definition). */
	UFUNCTION(BlueprintCallable, Category = "Roam|Region")
	FName GetCurrentRegionId() const { return CurrentRegionId; }

	const FRoamRegionDef* GetCurrentRegion() const;

	/** Region id at a world location. */
	UFUNCTION(BlueprintCallable, Category = "Roam|Region")
	FName GetRegionIdAt(FVector WorldLocation) const;

	/** Climate zone key ("Coast", "Valley", "DryHills", "Mountain") of the current region. */
	UFUNCTION(BlueprintCallable, Category = "Roam|Region")
	FName GetCurrentClimateZone() const;

	/** Traffic density multiplier of the region at a location (1 without data). */
	UFUNCTION(BlueprintCallable, Category = "Roam|Region")
	float GetTrafficDensityScaleAt(FVector WorldLocation) const;

	/**
	 * Resolves `tp` user text to a transform on the ground (traces down with the wheel channel). Returns false and fills OutError
	 * when the target is unknown or there is no world definition.
	 */
	bool ResolveTeleportTransform(const FString& Text, FTransform& OutTransform, FString& OutLabel, FString* OutError = nullptr) const;

	/** Shows the popup for the current region regardless of cooldown (debug menu / after fast travel). */
	void ForceRegionPopup();

	FRoamOnRegionChanged OnRegionChanged;

	/** The player must be this far (cm) outside the old region before it counts as left. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Region")
	float RegionHysteresisCm = 8000.0f;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Region")
	float RegionPopupCooldownSec = 20.0f;

private:
	URoamWorldDefinition* GetWorldDefinition() const;
	void SetCurrentRegion(FName NewRegionId, bool bPopup);

	FName CurrentRegionId;
	float PollAccumulator = 0.0f;
	double LastPopupTime = -1000.0;
	TMap<FName, double> LastPopupByRegion;
};
